import { useEffect, useState, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";

// ── Types ────────────────────────────────────────────────────────────────────

type ServiceStatus = "stopped" | "starting" | "running" | "error";

interface ServiceInfo {
  id: string;
  name: string;
  description: string;
  url: string | null;
  status: ServiceStatus;
  pid: number | null;
  port: number | null;
}

// ── Status badge ──────────────────────────────────────────────────────────────

function StatusDot({ status }: { status: ServiceStatus }) {
  const colors: Record<ServiceStatus, string> = {
    running: "bg-emerald-500 shadow-emerald-500/50",
    starting: "bg-amber-500 shadow-amber-500/50 animate-pulse",
    stopped: "bg-zinc-600",
    error: "bg-red-500 shadow-red-500/50",
  };
  const labels: Record<ServiceStatus, string> = {
    running: "Running",
    starting: "Starting…",
    stopped: "Stopped",
    error: "Error",
  };
  return (
    <div className="flex items-center gap-2">
      <span
        className={`inline-block w-2.5 h-2.5 rounded-full shadow-sm ${colors[status]}`}
      />
      <span className="text-xs font-medium text-zinc-400 uppercase tracking-wide">
        {labels[status]}
      </span>
    </div>
  );
}

// ── Service card ──────────────────────────────────────────────────────────────

function ServiceCard({
  service,
  onStart,
  onStop,
}: {
  service: ServiceInfo;
  onStart: (id: string) => void;
  onStop: (id: string) => void;
}) {
  const isRunning = service.status === "running";
  return (
    <div className="bg-zinc-800/50 border border-zinc-700/50 rounded-xl p-4 transition-colors hover:border-zinc-600/50">
      <div className="flex items-start justify-between mb-2">
        <div>
          <h3 className="text-sm font-semibold text-zinc-100">{service.name}</h3>
          <p className="text-xs text-zinc-500 mt-0.5">{service.description}</p>
        </div>
        <StatusDot status={service.status} />
      </div>

      <div className="flex items-center justify-between mt-3">
        <div className="text-xs text-zinc-500 space-y-0.5">
          {service.url && (
            <div>
              <span className="text-zinc-600">URL: </span>
              <span className="text-zinc-400 font-mono">{service.url}</span>
            </div>
          )}
          {service.pid && (
            <div>
              <span className="text-zinc-600">PID: </span>
              <span className="text-zinc-400 font-mono">{service.pid}</span>
            </div>
          )}
        </div>

        <div className="flex gap-2">
          {!isRunning ? (
            <button
              onClick={() => onStart(service.id)}
              className="px-3 py-1.5 text-xs font-medium bg-emerald-600 hover:bg-emerald-500 text-white rounded-lg transition-colors"
            >
              Start
            </button>
          ) : (
            <button
              onClick={() => onStop(service.id)}
              className="px-3 py-1.5 text-xs font-medium bg-zinc-700 hover:bg-zinc-600 text-zinc-200 rounded-lg transition-colors"
            >
              Stop
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

// ── Main App ──────────────────────────────────────────────────────────────────

export default function App() {
  const [services, setServices] = useState<ServiceInfo[]>([]);
  const [autoStarted, setAutoStarted] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  const refresh = useCallback(async () => {
    setRefreshing(true);
    try {
      const result = await invoke<ServiceInfo[]>("get_service_statuses");
      setServices(result);
    } catch (err) {
      console.error("Failed to get service statuses:", err);
    } finally {
      setRefreshing(false);
    }
  }, []);

  // Auto-start all services on first launch
  useEffect(() => {
    if (autoStarted) return;
    setAutoStarted(true);
    (async () => {
      try {
        const result = await invoke<ServiceInfo[]>("start_all_services");
        setServices(result);
      } catch (err) {
        console.error("Failed to auto-start services:", err);
        await refresh();
      }
    })();
  }, [autoStarted, refresh]);

  // Poll statuses every 3 seconds
  useEffect(() => {
    const interval = setInterval(refresh, 3000);
    return () => clearInterval(interval);
  }, [refresh]);

  const handleStart = async (id: string) => {
    try {
      await invoke("start_service", { id });
      await refresh();
    } catch (err) {
      console.error(`Failed to start ${id}:`, err);
    }
  };

  const handleStop = async (id: string) => {
    try {
      await invoke("stop_service", { id });
      await refresh();
    } catch (err) {
      console.error(`Failed to stop ${id}:`, err);
    }
  };

  const handleStartAll = async () => {
    try {
      const result = await invoke<ServiceInfo[]>("start_all_services");
      setServices(result);
    } catch (err) {
      console.error("Failed to start all:", err);
    }
  };

  const handleStopAll = async () => {
    try {
      const result = await invoke<ServiceInfo[]>("stop_all_services");
      setServices(result);
    } catch (err) {
      console.error("Failed to stop all:", err);
    }
  };

  const handleOpenUI = async () => {
    try {
      await invoke("open_agent_meow_ui");
    } catch (err) {
      console.error("Failed to open UI:", err);
    }
  };

  const runningCount = services.filter((s) => s.status === "running").length;

  return (
    <div className="min-h-screen bg-zinc-900 text-zinc-100 p-5">
      {/* Header */}
      <header className="mb-5">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-lg font-bold tracking-tight">Voice Stack</h1>
            <p className="text-xs text-zinc-500 mt-0.5">
              Handy + Voicebox + agent-meow
            </p>
          </div>
          <div className="text-xs text-zinc-500">
            {runningCount}/{services.length} services running
          </div>
        </div>
      </header>

      {/* Service cards */}
      <div className="space-y-3">
        {services.map((svc) => (
          <ServiceCard
            key={svc.id}
            service={svc}
            onStart={handleStart}
            onStop={handleStop}
          />
        ))}
        {services.length === 0 && (
          <div className="text-center py-8 text-zinc-500 text-sm">
            {refreshing ? "Loading…" : "No services found."}
          </div>
        )}
      </div>

      {/* Action bar */}
      <div className="mt-5 flex gap-2">
        <button
          onClick={handleStartAll}
          className="flex-1 px-4 py-2 text-sm font-medium bg-emerald-600 hover:bg-emerald-500 text-white rounded-lg transition-colors"
        >
          Start All
        </button>
        <button
          onClick={handleStopAll}
          className="flex-1 px-4 py-2 text-sm font-medium bg-zinc-700 hover:bg-zinc-600 text-zinc-200 rounded-lg transition-colors"
        >
          Stop All
        </button>
      </div>

      {/* Open agent-meow UI button */}
      <button
        onClick={handleOpenUI}
        disabled={runningCount < services.length}
        className="w-full mt-3 px-4 py-2 text-sm font-medium bg-indigo-600 hover:bg-indigo-500 disabled:opacity-40 disabled:cursor-not-allowed text-white rounded-lg transition-colors"
      >
        Open agent-meow Web UI ↗
      </button>

      {/* Footer */}
      <footer className="mt-6 pt-4 border-t border-zinc-800 text-center">
        <p className="text-xs text-zinc-600">
          Voice Stack v0.1.0 ·{" "}
          <span className="text-zinc-500">
            Closing this window stops all services
          </span>
        </p>
      </footer>
    </div>
  );
}
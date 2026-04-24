import React, { useEffect, useState } from 'react';
import { useAppSelector } from '../../redux/hooks';
import Accordion from '../common/Accordion';
import { api } from '../../services/api';
import '../../assets/css/RightPanel.css';

const DEVICE_COLORS: Record<string, string> = {
  GPU: '#1565c0',
  CPU: '#2e7d32',
  NPU: '#6a1b9a',
};

const STATUS_DOT: Record<string, { color: string; label: string }> = {
  running: { color: '#4caf50', label: 'Running' },
  stopped: { color: '#9e9e9e', label: 'Idle' },
  error:   { color: '#f44336', label: 'Error' },
};

const WORKLOAD_DEFS = [
  { name: 'Person Detection',   models: 'person-detect-fp32',   deviceKey: 'detect', fallbackKey: 'detect' },
  { name: 'Patient Detection',  models: 'patient-detect-fp32',  deviceKey: 'detect', fallbackKey: 'detect' },
  { name: 'Latch Detection',    models: 'latch-detect-fp32',    deviceKey: 'detect', fallbackKey: 'detect' },
  { name: 'rPPG',               models: 'MTTS-CAN',             deviceKey: 'rppg',   fallbackKey: 'rppg' },
  { name: 'Action Recognition', models: 'Encoder / Decoder',    deviceKey: 'action', fallbackKey: 'action' },
] as const;

export function PipelinePerformanceAccordion() {
  const systemStatus = useAppSelector((state) => state.nicu.data.systemStatus);
  const pipelinePerf = useAppSelector((state) => state.nicu.data.pipelinePerformance);
  const [devices, setDevices] = useState({ detect: 'GPU', rppg: 'CPU', action: 'NPU' });
  const [fallback, setFallback] = useState<Record<string, { original: string; fallback: string }> | null>(null);

  useEffect(() => {
    const fetchCfg = () => {
      api.getConfig().then(c => {
        if (c.devices) setDevices(c.devices);
        setFallback(c.fallback || null);
      }).catch(() => {});
    };
    fetchCfg();
    const id = setInterval(fetchCfg, 10000);
    return () => clearInterval(id);
  }, []);

  const isRunning = systemStatus === 'running' || systemStatus === 'starting';
  const status = isRunning ? 'running' : 'stopped';

  const sseLookup: Record<string, { fps?: number; latency_ms?: number; device?: string; status?: string }> = {};
  if (pipelinePerf?.workloads) {
    for (const w of pipelinePerf.workloads) {
      sseLookup[w.name] = w;
    }
  }

  const thStyle: React.CSSProperties = {
    padding: '8px 10px', color: '#fff', fontWeight: 600, fontSize: '11px',
    textTransform: 'uppercase', letterSpacing: '0.4px', textAlign: 'left', border: '1px solid #888',
  };

  return (
    <Accordion title="Pipeline Performance" defaultOpen>
      <div className="pipeline-perf">
        {isRunning && pipelinePerf?.pipeline_fps > 0 && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8, fontSize: '12px', color: '#555' }}>
            <span style={{ fontWeight: 600, color: '#24292f' }}>Pipeline FPS:</span>
            <span style={{ fontFamily: 'monospace', fontWeight: 700, fontSize: '14px', color: '#1565c0' }}>
              {pipelinePerf.pipeline_fps.toFixed(1)}
            </span>
            <span style={{ fontSize: '10px', color: '#999' }}>({pipelinePerf.decode})</span>
          </div>
        )}

        <table style={{
          width: '100%',
          borderCollapse: 'collapse',
          fontSize: '12px',
          border: '2px solid #888',
        }}>
          <thead>
            <tr style={{ background: '#3a3f47' }}>
              <th style={thStyle}>Workload</th>
              <th style={thStyle}>Model</th>
              <th style={thStyle}>Device</th>
              <th style={thStyle}>FPS</th>
              <th style={thStyle}>Latency</th>
              <th style={thStyle}>Status</th>
            </tr>
          </thead>
          <tbody>
            {WORKLOAD_DEFS.map((def, i) => {
              const device = (devices as Record<string, string>)[def.deviceKey] || 'CPU';
              const sseRow = sseLookup[def.name] || {};
              const actualDevice = sseRow.device || device;
              const devColor = DEVICE_COLORS[actualDevice] || '#555';
              const actualStatus = sseRow.status || status;
              const statusInfo = STATUS_DOT[actualStatus] || STATUS_DOT.stopped;
              const rowBg = i % 2 === 0 ? '#fff' : '#f4f5f7';
              const cellStyle: React.CSSProperties = { padding: '8px 10px', border: '1px solid #bbb', verticalAlign: 'middle' };
              const isFallback = fallback && fallback[def.fallbackKey];
              const fps = sseRow.fps ?? (isRunning && pipelinePerf?.pipeline_fps ? pipelinePerf.pipeline_fps : null);
              const latency = sseRow.latency_ms ?? null;

              return (
                <tr key={def.name} style={{ background: rowBg }}>
                  <td style={{ ...cellStyle, fontWeight: 500, color: '#24292f' }}>{def.name}</td>
                  <td style={{ ...cellStyle, fontSize: '10px', color: '#888', fontFamily: 'monospace' }}>{def.models}</td>
                  <td style={cellStyle}>
                    <span style={{
                      display: 'inline-block',
                      padding: '2px 10px',
                      border: '1px solid',
                      borderRadius: '10px',
                      fontFamily: 'monospace',
                      fontWeight: 700,
                      fontSize: '10px',
                      backgroundColor: devColor + '14',
                      color: devColor,
                      borderColor: devColor + '40',
                    }}>
                      {actualDevice}
                    </span>
                    {isFallback && (
                      <span style={{
                        display: 'inline-block',
                        marginLeft: '4px',
                        padding: '1px 6px',
                        borderRadius: '8px',
                        fontSize: '9px',
                        fontWeight: 600,
                        backgroundColor: '#fff3e0',
                        color: '#e65100',
                        border: '1px solid #ffcc80',
                      }}>
                        fallback
                      </span>
                    )}
                  </td>
                  <td style={{ ...cellStyle, fontFamily: 'monospace', fontWeight: 600, fontSize: '11px', color: isRunning ? '#24292f' : '#ccc' }}>
                    {fps !== null ? fps.toFixed(1) : '—'}
                  </td>
                  <td style={{ ...cellStyle, fontFamily: 'monospace', fontSize: '11px', color: latency !== null ? '#24292f' : '#ccc' }}>
                    {latency !== null ? `${latency.toFixed(1)} ms` : '\u2014'}
                  </td>
                  <td style={cellStyle}>
                    <span style={{
                      display: 'inline-block',
                      width: '8px',
                      height: '8px',
                      borderRadius: '50%',
                      marginRight: '6px',
                      verticalAlign: 'middle',
                      backgroundColor: statusInfo.color,
                    }} />
                    <span style={{ fontSize: '11px', color: '#555', fontWeight: 500 }}>{statusInfo.label}</span>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </Accordion>
  );
}

export default PipelinePerformanceAccordion;

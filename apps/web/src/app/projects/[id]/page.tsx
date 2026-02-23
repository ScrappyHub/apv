"use client";

import { useEffect, useState } from "react";
import { supabase } from "../../../lib/supabase";

type Run = { id: string; created_at: string; status: string; verdict: string | null };

export default function ProjectDetail({ params }: { params: { id: string } }){
  const projectId = params.id;
  const [runs,setRuns] = useState<Run[]>([]);
  const [msg,setMsg] = useState<string | null>(null);

  async function refresh(){
    setMsg(null);
    const { data, error } = await supabase
      .from("apv.runs")
      .select("id,created_at,status,verdict")
      .eq("project_id", projectId)
      .order("created_at", { ascending: false });

    if(error){ setMsg(error.message); return; }
    setRuns((data ?? []) as any);
  }

  useEffect(() => { refresh(); }, []);

  return (
    <div style={{ maxWidth: 720 }}>
      <h2>Project</h2>
      <div style={{ opacity: 0.7 }}>id: {projectId}</div>
      {msg ? <div style={{ color: "tomato", marginTop: 12 }}>{msg}</div> : null}

      <h3 style={{ marginTop: 16 }}>Runs</h3>
      <ul>
        {runs.map(r => (
          <li key={r.id}>
            <b>{r.status}</b> {r.verdict ? <span>({r.verdict})</span> : null}{" "}
            <span style={{ opacity: 0.7 }}>{new Date(r.created_at).toLocaleString()}</span>
          </li>
        ))}
      </ul>

      <p style={{ opacity: 0.7 }}>
        Upload + enqueue + worker execution is next.
      </p>
    </div>
  );
}

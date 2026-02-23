"use client";

import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";

type Project = { id: string; title: string; created_at: string };

export default function ProjectsPage(){
  const [projects,setProjects] = useState<Project[]>([]);
  const [title,setTitle] = useState("");
  const [msg,setMsg] = useState<string | null>(null);

  async function refresh(){
    setMsg(null);
    const { data, error } = await supabase
      .from("apv.projects")
      .select("id,title,created_at")
      .order("created_at", { ascending: false });

    if(error){ setMsg(error.message); return; }
    setProjects((data ?? []) as any);
  }

  useEffect(() => { refresh(); }, []);

  async function create(){
    setMsg(null);
    if(!title.trim()){ setMsg("Title required"); return; }
    const { error } = await supabase.from("apv.projects").insert({ title });
    if(error){ setMsg(error.message); return; }
    setTitle("");
    await refresh();
  }

  return (
    <div style={{ maxWidth: 720 }}>
      <h2>Projects</h2>
      <div style={{ display: "flex", gap: 8, marginBottom: 12 }}>
        <input placeholder="New project title" value={title} onChange={e=>setTitle(e.target.value)} style={{ flex: 1 }} />
        <button onClick={create}>Create</button>
      </div>
      {msg ? <div style={{ color: "tomato" }}>{msg}</div> : null}
      <ul>
        {projects.map(p => (
          <li key={p.id}>
            <a href={`/projects/${p.id}`}>{p.title}</a>{" "}
            <span style={{ opacity: 0.7 }}>({new Date(p.created_at).toLocaleString()})</span>
          </li>
        ))}
      </ul>
      <p style={{ opacity: 0.7 }}>
        Runs/upload UI comes next (Tier-1 step 2).
      </p>
    </div>
  );
}

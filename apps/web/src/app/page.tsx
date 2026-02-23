"use client";

import { useEffect, useState } from "react";
import { supabase } from "../lib/supabase";

export default function HomePage(){
  const [email,setEmail] = useState("");
  const [pw,setPw] = useState("");
  const [msg,setMsg] = useState<string | null>(null);
  const [user,setUser] = useState<any>(null);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setUser(data.user ?? null));
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setUser(s?.user ?? null));
    return () => { sub.subscription.unsubscribe(); };
  }, []);

  async function signIn(){
    setMsg(null);
    const { error } = await supabase.auth.signInWithPassword({ email, password: pw });
    if(error) setMsg(error.message);
  }

  async function signUp(){
    setMsg(null);
    const { error } = await supabase.auth.signUp({ email, password: pw });
    if(error) setMsg(error.message);
    else setMsg("Sign-up OK. If email confirmations are enabled, check inbox.");
  }

  async function signOut(){
    await supabase.auth.signOut();
  }

  return (
    <div style={{ maxWidth: 640 }}>
      {!user ? (
        <>
          <h2>Login</h2>
          <div style={{ display: "grid", gap: 8 }}>
            <input placeholder="email" value={email} onChange={e=>setEmail(e.target.value)} />
            <input placeholder="password" type="password" value={pw} onChange={e=>setPw(e.target.value)} />
            <div style={{ display: "flex", gap: 8 }}>
              <button onClick={signIn}>Sign In</button>
              <button onClick={signUp}>Sign Up</button>
            </div>
            {msg ? <div style={{ color: "tomato" }}>{msg}</div> : null}
          </div>
          <p style={{ opacity: 0.7, marginTop: 16 }}>
            Next: build Projects/Runs screens + upload.
          </p>
        </>
      ) : (
        <>
          <h2>Signed in</h2>
          <div style={{ opacity: 0.8 }}>uid: {user.id}</div>
          <div style={{ marginTop: 12 }}>
            <a href="/projects">Go to Projects</a>
          </div>
          <div style={{ marginTop: 12 }}>
            <button onClick={signOut}>Sign Out</button>
          </div>
        </>
      )}
    </div>
  );
}

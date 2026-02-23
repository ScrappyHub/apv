import express from "express";
import { createClient } from "@supabase/supabase-js";

function die(m){ throw new Error(m); }

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if(!SUPABASE_URL) die("MISSING_ENV: SUPABASE_URL");
if(!SUPABASE_SERVICE_ROLE_KEY) die("MISSING_ENV: SUPABASE_SERVICE_ROLE_KEY");

const supa = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false }
});

const app = express();
app.use(express.json({ limit: "2mb" }));

app.get("/health", (_req,res) => res.json({ ok: true }));

app.post("/runs/:id/enqueue", async (req,res) => {
  const id = req.params.id;
  const { data, error } = await supa
    .from("apv.runs")
    .update({ status: "queued" })
    .eq("id", id)
    .select("id,status")
    .maybeSingle();

  if(error) return res.status(500).json({ ok:false, error: error.message });
  if(!data) return res.status(404).json({ ok:false, error: "NOT_FOUND" });
  return res.json({ ok:true, run: data });
});

const port = process.env.PORT ? parseInt(process.env.PORT,10) : 8787;
app.listen(port, () => {
  console.log(`APV_API_OK listening on :${port}`);
});

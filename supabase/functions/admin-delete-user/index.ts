import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) throw new Error("Missing authorization");

    const userClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } }
    );

    const { data: { user: caller }, error: callerError } = await userClient.auth.getUser();
    if (callerError || !caller) throw new Error("Unauthenticated");

    const { data: admin, error: adminError } = await userClient
      .from("user_roles").select("role").eq("user_id", caller.id).maybeSingle();

    if (adminError || admin?.role !== "admin") throw new Error("Admin access required");

    const body = await req.json();
    const targetUserId = String(body.user_id || "");
    if (!targetUserId || targetUserId === caller.id) throw new Error("Invalid target user");

    const service = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const { error } = await service.auth.admin.deleteUser(targetUserId);
    if (error) throw error;

    return new Response(JSON.stringify({ ok: true }), {
      status: 200, headers: { ...cors, "Content-Type": "application/json" }
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: e.message || "Delete failed" }), {
      status: 400, headers: { ...cors, "Content-Type": "application/json" }
    });
  }
});
import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from "./config.js";

// GitHub Pages cannot keep a browser key secret. This must be the publishable/anon key only.
// Never put SUPABASE_SERVICE_ROLE_KEY in this file or any frontend asset.
export const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
});

export async function currentUser() {
  const { data, error } = await supabase.auth.getUser();
  if (error) return null;
  return data.user;
}

export function appUrl(path) {
  const base = new URL("../", import.meta.url);
  return new URL(path.replace(/^\//, ""), base).href;
}

export async function requireAuth() {
  const user = await currentUser();
  if (!user) {
    location.replace(appUrl("login.html"));
    throw new Error("Not authenticated");
  }
  return user;
}

export async function getProfile(userId) {
  const { data, error } = await supabase.from("profiles").select("*").eq("id", userId).single();
  if (error) throw error;
  return data;
}

export async function getRole(userId) {
  const { data, error } = await supabase.from("user_roles").select("role").eq("user_id", userId).maybeSingle();
  if (error) throw error;
  return data?.role || "user";
}

export async function ensureActive(userId) {
  const { data, error } = await supabase.from("profiles").select("account_status").eq("id", userId).single();
  if (error) throw error;
  if (data.account_status !== "active") {
    await supabase.auth.signOut();
    throw new Error("Your account has been disabled. Please contact the administrator.");
  }
}

export function money(value, currency="LKR") {
  try { return new Intl.NumberFormat(undefined,{style:"currency",currency}).format(Number(value||0)); }
  catch { return `${currency} ${Number(value||0).toFixed(2)}`; }
}

export function esc(v="") {
  return String(v).replace(/[&<>"']/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
}

export function toast(message, error=false) {
  const el=document.createElement("div"); el.className="toast"+(error?" error":""); el.textContent=message;
  document.body.appendChild(el); setTimeout(()=>el.remove(),3200);
}

export function navShell(title, active, profile, isAdmin=false) {
  const nav = [
    ["dashboard.html","Dashboard","📊"],
    ["invoices.html","Invoices","🧾"],
    ["invoice-editor.html","Create Invoice","＋"],
    ["customers.html","Customers","👥"],
    ["products.html","Products & Services","📦"],
    ["settings.html","Settings","⚙️"]
  ];
  return `<div class="layout"><aside class="sidebar" id="sidebar"><div class="brand">Invoice<span>Pro</span></div><nav>
    ${nav.map(([href,label,icon])=>`<a class="nav ${active===label?'active':''}" href="${href}">${icon} &nbsp;${label}</a>`).join("")}
    ${isAdmin?`<a class="nav ${active==="Admin"?'active':''}" href="admin/index.html">🛡️ &nbsp;Admin</a>`:""}
  </nav><div class="sidebar-bottom"><button id="logoutBtn" class="btn ghost full" style="color:#fff;border-color:#374151">Logout</button></div></aside>
  <main class="main"><div class="topbar"><div><button class="btn ghost mobile-menu" id="menuBtn">☰</button> <h1 style="display:inline">${esc(title)}</h1></div>
  <div class="top-actions"><span class="user-pill">${esc(profile?.business_name||profile?.full_name||"Account")}</span></div></div>`;
}

export function closeShell(){ return `</main></div>`; }

export function debounce(fn, wait=300) {
  let timer;
  return (...args) => { clearTimeout(timer); timer=setTimeout(() => fn(...args), wait); };
}

export function wireShell() {
  document.getElementById("logoutBtn")?.addEventListener("click", async()=>{await supabase.auth.signOut();location.href="login.html";});
  document.getElementById("menuBtn")?.addEventListener("click",()=>document.getElementById("sidebar")?.classList.toggle("open"));
}

let bootPromise = null;
export async function boot(active, title) {
  if (bootPromise) return bootPromise;
  bootPromise = (async () => {
    const user=await requireAuth();
    await ensureActive(user.id);
    const [profile, role]=await Promise.all([getProfile(user.id),getRole(user.id)]);
  document.documentElement.classList.toggle("dark", localStorage.getItem("theme")==="dark");
  document.getElementById("app").innerHTML=navShell(title,active,profile,role==="admin")+`</main></div>`;
    wireShell();
    return {user,profile,role};
  })().catch(error => { bootPromise=null; throw error; });
  return bootPromise;
}

export function setTheme(theme){ localStorage.setItem("theme",theme); document.documentElement.classList.toggle("dark",theme==="dark"); }

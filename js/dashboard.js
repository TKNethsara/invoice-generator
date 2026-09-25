import { supabase, boot, closeShell, money, esc, toast } from "./supabase.js";

const {user,profile,role}=await boot("Dashboard","Dashboard");
const app=document.getElementById("app");

async function load(){
  const {data: invoices,error}=await supabase.from("invoices").select("id,invoice_number,invoice_date,due_date,total,status,currency,customers(name)").order("created_at",{ascending:false}).limit(8);
  if(error){toast(error.message,true);return;}
  const all=await supabase.from("invoices").select("status,total,currency");
  if(all.error){toast(all.error.message,true);return;}
  const rows=all.data||[];
  const paid=rows.filter(x=>x.status==="paid"), pending=rows.filter(x=>["pending","overdue","draft"].includes(x.status));
  const rev=paid.reduce((s,x)=>s+Number(x.total||0),0), prev=pending.reduce((s,x)=>s+Number(x.total||0),0);
  const currency=profile?.id ? (rows[0]?.currency||"LKR") : "LKR";
  app.insertAdjacentHTML("beforeend",`
  <div class="grid stats">
    <div class="card stat"><div class="label">Total Invoices</div><div class="value">${rows.length}</div></div>
    <div class="card stat"><div class="label">Paid Invoices</div><div class="value">${paid.length}</div></div>
    <div class="card stat"><div class="label">Pending</div><div class="value">${rows.filter(x=>x.status==="pending").length}</div></div>
    <div class="card stat"><div class="label">Overdue</div><div class="value">${rows.filter(x=>x.status==="overdue").length}</div></div>
    <div class="card stat"><div class="label">Total Revenue</div><div class="value">${money(rev,currency)}</div></div>
    <div class="card stat"><div class="label">Pending Revenue</div><div class="value">${money(prev,currency)}</div></div>
  </div>
  <div class="card section" style="margin-top:16px"><div class="section-head"><h2>Recent Invoices</h2><a class="btn primary" href="invoice-editor.html">＋ Create New Invoice</a></div>
  <div class="table-wrap"><table class="table"><thead><tr><th>Invoice</th><th>Customer</th><th>Date</th><th>Due</th><th>Amount</th><th>Status</th><th>Actions</th></tr></thead><tbody>
  ${(invoices||[]).map(i=>`<tr><td>${esc(i.invoice_number)}</td><td>${esc(i.customers?.name||"—")}</td><td>${esc(i.invoice_date)}</td><td>${esc(i.due_date)}</td><td>${money(i.total,i.currency)}</td><td><span class="badge ${i.status}">${esc(i.status)}</span></td><td><a class="btn ghost mini" href="invoice-detail.html?id=${i.id}">View</a></td></tr>`).join("")||`<tr><td colspan="7" class="empty">No invoices yet — create your first invoice.</td></tr>`}
  </tbody></table></div></div>
  <div class="grid two" style="margin-top:16px"><div class="card section"><div class="section-head"><h2>Monthly Revenue</h2></div><canvas id="revenueChart" height="170"></canvas></div>
  <div class="card section"><h2>Quick actions</h2><div style="display:grid;gap:9px;margin-top:14px"><a class="btn secondary" href="customers.html">Manage Customers</a><a class="btn secondary" href="products.html">Manage Products</a><a class="btn secondary" href="settings.html">Business Settings</a>${role==="admin"?`<a class="btn secondary" href="admin/index.html">Admin Dashboard</a>`:""}</div></div></div>`);
  drawChart(rows);
}
function drawChart(rows){
  const c=document.getElementById("revenueChart"),ctx=c.getContext("2d"), months=Array.from({length:6},(_,i)=>{let d=new Date();d.setMonth(d.getMonth()-5+i);return {key:`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}`,label:d.toLocaleString(undefined,{month:"short"})};});
  const vals=months.map(m=>rows.filter(x=>x.status==="paid" && String(x.created_at||"").startsWith(m.key)).reduce((s,x)=>s+Number(x.total||0),0));
  const max=Math.max(...vals,1),w=c.width=c.clientWidth*2,h=c.height=c.height*2;ctx.scale(2,2);const W=c.clientWidth,H=c.height/2;ctx.clearRect(0,0,W,H);ctx.strokeStyle="#cbd5e1";ctx.fillStyle="#4f46e5";ctx.lineWidth=2;
  vals.forEach((v,i)=>{const x=35+i*(W-55)/(vals.length-1),y=H-25-(v/max)*(H-50);if(i)ctx.lineTo(x,y);else ctx.moveTo(x,y)});ctx.stroke();
  vals.forEach((v,i)=>{const x=35+i*(W-55)/(vals.length-1),y=H-25-(v/max)*(H-50);ctx.beginPath();ctx.arc(x,y,4,0,Math.PI*2);ctx.fill();ctx.fillStyle="#64748b";ctx.font="11px sans-serif";ctx.fillText(months[i].label,x-9,H-7);ctx.fillStyle="#4f46e5";});
}
load();

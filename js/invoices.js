import { supabase, boot, money, esc, toast, debounce } from "./supabase.js";
const {profile}=await boot("Invoices","Invoices"); const app=document.getElementById("app");
let filter="all", query="";
app.insertAdjacentHTML("beforeend",`<div class="card section"><div class="section-head"><h2>Invoice Management</h2><a class="btn primary" href="invoice-editor.html">＋ New Invoice</a></div>
<div class="toolbar"><input id="search" placeholder="Search invoice number or customer…"><div class="tabs">${["all","draft","pending","paid","overdue","cancelled"].map(x=>`<button class="tab ${x==="all"?"active":""}" data-filter="${x}">${x}</button>`).join("")}</div></div><div id="invoiceList"></div></div>`);
async function load(){
  let q=supabase.from("invoices").select("id,invoice_number,invoice_date,due_date,total,status,currency,customers(name)").order("created_at",{ascending:false}).limit(100);
  if(filter!=="all")q=q.eq("status",filter);
  if(query)q=q.ilike("invoice_number",`%${query}%`);
  const {data,error}=await q;if(error){toast(error.message,true);return;}
  document.getElementById("invoiceList").innerHTML=`<div class="table-wrap"><table class="table"><thead><tr><th>Invoice</th><th>Customer</th><th>Date</th><th>Due</th><th>Amount</th><th>Status</th><th>Actions</th></tr></thead><tbody>${(data||[]).map(i=>`<tr><td>${esc(i.invoice_number)}</td><td>${esc(i.customers?.name||"—")}</td><td>${i.invoice_date}</td><td>${i.due_date}</td><td>${money(i.total,i.currency)}</td><td><span class="badge ${i.status}">${i.status}</span></td><td class="actions"><a class="btn ghost mini" href="invoice-detail.html?id=${i.id}">View</a><a class="btn ghost mini" href="invoice-editor.html?id=${i.id}">Edit</a></td></tr>`).join("")||`<tr><td colspan="7" class="empty">No invoices found.</td></tr>`}</tbody></table></div>`;
}
document.getElementById("search").oninput=debounce(e=>{query=e.target.value.trim();load()},300);document.querySelectorAll(".tab").forEach(b=>b.onclick=()=>{filter=b.dataset.filter;document.querySelectorAll(".tab").forEach(x=>x.classList.remove("active"));b.classList.add("active");load()});load();

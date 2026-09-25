import { supabase, getRole, getProfile, ensureActive, toast } from "./supabase.js";

const msg=document.getElementById("authMsg");
function show(t,err=true){ if(msg){msg.textContent=t;msg.style.color=err?"#dc2626":"#15803d";} }

document.getElementById("loginForm")?.addEventListener("submit",async e=>{
  e.preventDefault();
  const email=document.getElementById("email").value.trim(), password=document.getElementById("password").value;
  const remember=document.getElementById("remember").checked;
  try{
    if(!remember) sessionStorage.setItem("invoicepro_no_persist","1");
    const {error}=await supabase.auth.signInWithPassword({email,password});
    if(error) throw error;
    const {data:{user}}=await supabase.auth.getUser();
    await ensureActive(user.id);
    const role=await getRole(user.id);
    location.href=role==="admin"?"admin/index.html":"dashboard.html";
  }catch(err){show(err.message||"Unable to sign in.");}
});

document.getElementById("registerForm")?.addEventListener("submit",async e=>{
  e.preventDefault();
  const full_name=document.getElementById("fullName").value.trim();
  const business_name=document.getElementById("businessName").value.trim();
  const email=document.getElementById("email").value.trim();
  const password=document.getElementById("password").value;
  try{
    const {data,error}=await supabase.auth.signUp({email,password,options:{data:{full_name,business_name}}});
    if(error) throw error;
    if(!data.user) throw new Error("Registration did not complete.");
    show("Account created. Check your email if confirmation is enabled, then sign in.",false);
  }catch(err){show(err.message||"Unable to register.");}
});

document.getElementById("forgotBtn")?.addEventListener("click",async()=>{
  const email=document.getElementById("email").value.trim();
  if(!email)return show("Enter your email first.");
  try{
    const {error}=await supabase.auth.resetPasswordForEmail(email,{redirectTo:`${location.origin}/settings.html`});
    if(error)throw error; show("Password reset email sent.",false);
  }catch(e){show(e.message||"Unable to send reset email.");}
});

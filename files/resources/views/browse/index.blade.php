<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Browse Modpacks</title>
<style>
body{background:#14151c;color:#e2e8f0;font-family:system-ui,sans-serif;margin:0;padding:20px}
.wrap{max-width:1200px;margin:0 auto}
h1{color:#fff;text-align:center}
.providers{display:flex;gap:12px;margin:20px 0}
.providers button{flex:1;padding:18px;font-size:18px;font-weight:700;border:0;border-radius:10px;cursor:pointer;color:#fff;background:#2a2d3a}
.providers button.active-modrinth{background:#16a34a}
.providers button.active-curseforge{background:#ea580c}
.providers button.active-ftb{background:#2563eb}
.bar{display:flex;gap:8px;margin:12px 0}
.bar input,.bar select{background:#1a1c23;color:#fff;border:1px solid #3a3d4a;padding:10px;border-radius:6px}
.bar input{flex:1}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:12px;margin-top:12px}
.card{background:#2a2d3a;border-radius:10px;padding:14px;border:2px solid transparent;cursor:pointer}
.card:hover{border-color:#2480eb}
.card img{width:56px;height:56px;border-radius:8px;float:left;margin-right:10px;object-fit:cover}
.card h3{margin:0;color:#fff;font-size:15px}
.card p{font-size:12px;color:#94a3b8;margin:4px 0}
.card .desc{font-size:13px;color:#cbd5e1;min-height:36px}
.install{background:#2480eb;color:#fff;border:0;width:100%;padding:10px;border-radius:6px;margin-top:10px;cursor:pointer;font-weight:700}
.install:hover{background:#1a6ed8}
.modal{position:fixed;inset:0;background:rgba(0,0,0,.7);display:none;align-items:center;justify-content:center;z-index:50}
.modal.open{display:flex}
.box{background:#2a2d3a;border-radius:10px;padding:20px;max-width:600px;width:90%;max-height:80vh;overflow:auto}
.ver{padding:10px;background:#1a1c23;border-radius:6px;margin:6px 0;display:flex;justify-content:space-between;align-items:center;cursor:pointer}
.ver:hover{background:#3a3d4a}
.status{text-align:center;color:#94a3b8;padding:16px}
.ids{background:#1a1c23;padding:12px;border-radius:6px;font-family:monospace;margin-top:12px}
</style>
</head>
<body>
<div class="wrap">
<h1>Browse Modpacks</h1>
<div class="providers">
<button id="b-modrinth" onclick="setP('modrinth')">Modrinth<br><small>18,000+</small></button>
<button id="b-curseforge" onclick="setP('curseforge')">CurseForge<br><small>10,000+</small></button>
<button id="b-ftb" onclick="setP('ftb')">Feed The Beast<br><small>94</small></button>
</div>
<div class="bar">
<input id="q" placeholder="Search modpacks..." onkeydown="if(event.key==='Enter')search()">
<select id="sort"><option value="downloads">Most popular</option><option value="newest">Newest</option><option value="updated">Updated</option></select>
<button class="install" style="width:auto" onclick="search()">Search</button>
</div>
<div id="status" class="status">Loading...</div>
<div id="grid" class="grid"></div>
<div id="pager" style="text-align:center;margin:16px"></div>
</div>
<div id="modal" class="modal"><div class="box"><div id="mbox"></div><button class="install" onclick="closeM()">Close</button></div></div>
<script>
let provider='modrinth',page=1,items=[],total=0;const PS=24;
const api=(u)=>fetch(u,{credentials:'same-origin',headers:{'X-Requested-With':'XMLHttpRequest','Accept':'application/json'}});
function setP(p){provider=p;page=1;
document.getElementById('b-modrinth').className=provider==='modrinth'?'active-modrinth':'';
document.getElementById('b-curseforge').className=provider==='curseforge'?'active-curseforge':'';
document.getElementById('b-ftb').className=provider==='ftb'?'active-ftb':'';
search();}
async function search(){
const q=document.getElementById('q').value,sort=document.getElementById('sort').value;
const st=document.getElementById('status'),g=document.getElementById('grid');
st.textContent='Loading '+provider+'...';g.innerHTML='';
try{
if(provider==='modrinth'){
const p=new URLSearchParams({query:q,limit:PS,offset:(page-1)*PS,index:sort});
p.set('facets','[["project_type:modpack"]]');
const r=await fetch('https://api.modrinth.com/v2/search?'+p);const d=await r.json();
items=(d.hits||[]).map(h=>({id:h.project_id,name:h.title,desc:h.description,dl:h.downloads,logo:h.icon_url,author:h.author,provider:'modrinth'}));total=d.total_hits||0;
}else if(provider==='curseforge'){
const r=await api('/api/client/modpacks/curseforge/search?q='+encodeURIComponent(q)+'&page='+(page-1));
const d=await r.json();items=d.items||[];total=d.total||0;
items=items.map(m=>({...m,provider:'curseforge'}));
}else{
const r=await api('/api/client/modpacks/ftb-list');const d=await r.json();
let all=d.items||[];const ql=q.toLowerCase();
if(ql)all=all.filter(m=>m.name.toLowerCase().includes(ql));
total=all.length;const s=(page-1)*PS;items=all.slice(s,s+PS).map(m=>({...m,provider:'ftb',dl:m.installs,author:m.author||'FTB'}));
}
st.textContent='Showing '+items.length+' of '+total.toLocaleString()+' ('+provider+')';
g.innerHTML=items.map((m,i)=>`<div class="card" onclick="vers(${i})">${m.logo?`<img src="${m.logo}" onerror="this.style.display='none'">`:''}<div><h3>${m.name}</h3><p>by ${m.author||'?'} • ${(m.dl||m.downloads||0).toLocaleString()}</p><div class="desc">${(m.summary||m.desc||'').substring(0,110)}</div><button class="install" onclick="event.stopPropagation();vers(${i})">Install</button></div></div>`).join('')||'<p>No modpacks found.</p>';
let tp=Math.max(1,Math.ceil(total/PS));
document.getElementById('pager').innerHTML=(page>1?`<button class="install" style="width:auto" onclick="go(${page-1})">Prev</button>`:'')+` Page ${page} / ${tp} `+(page<tp?`<button class="install" style="width:auto" onclick="go(${page+1})">Next</button>`:'');
}catch(e){st.textContent='Error: '+e.message;}
}
function go(n){page=n;search();}
async function vers(i){
const m=items[i];const mb=document.getElementById('mbox');
document.getElementById('modal').classList.add('open');
mb.innerHTML=`<h2 style="color:#fff">${m.name}</h2><p>Loading versions...</p>`;
let vs=[];
if(m.provider==='modrinth'){const r=await fetch('https://api.modrinth.com/v2/project/'+m.id+'/version');vs=await r.json();}
else if(m.provider==='curseforge'){const r=await api('/api/client/modpacks/curseforge/versions/'+m.id);const d=await r.json();vs=d.items||[];}
else{const r=await api('/api/client/modpacks/ftb-versions/'+m.id);const d=await r.json();vs=d.items||[];}
mb.innerHTML=`<h2 style="color:#fff">${m.name}</h2>`+vs.slice(0,20).map(v=>`<div class="ver" onclick="pick('${m.id}','${v.id}','${m.name.replace(/'/g,"")}','${m.provider}','${v.gameVersion||''}','${v.loader||''}')"><div><b style="color:#fff">${v.name}</b><div style="font-size:12px;color:#94a3b8">MC ${v.gameVersion||v.gameVersion} • ${v.loader||''}</div></div><button class="install" style="width:auto">Install</button></div>`).join('');
}
async function pick(pid,vid,name,prov,mc,loader){
const t=`Project ID: ${pid}\nVersion ID: ${vid}\nProvider: ${prov}`;
try{await navigator.clipboard.writeText(t);}catch(e){prompt('Copy this:',t);}
localStorage.setItem('modpack_pick',JSON.stringify({pid,vid,prov,mc,loader}));
alert('Saved!\n'+t+'\n\nGo back to the Create Server tab, make sure the Modrinth Generic egg is selected, click anywhere on the page - the IDs fill in automatically.');
}
function closeM(){document.getElementById('modal').classList.remove('open');}
setP('modrinth');
</script>
</body>
</html>

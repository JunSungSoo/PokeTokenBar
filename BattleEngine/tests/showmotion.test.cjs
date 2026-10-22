const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {spawn}=require('node:child_process');
const {once}=require('node:events');
const root=path.join(__dirname,'../../Sources/PokeTokenBar/Resources/Showmotion');
test('Showmotion effects and GPU runtime are byte-identical to the pinned originals',()=>{
 const source=JSON.parse(fs.readFileSync(path.join(root,'source-sha256.json')));
 assert.equal(source.revision,'76aaa0b2ae4f3fbe49a4024ae2b6521038cf6d50');
 for(const[name,hash]of Object.entries(source.files))assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(root,name))).digest('hex'),hash,name);
 const manifest=JSON.parse(fs.readFileSync(path.join(root,'libs/effects/manifest.json')));
 assert.equal(Object.keys(manifest).length,9);
 for(const id of Object.keys(manifest))assert.ok(fs.statSync(path.join(root,`libs/effects/${id}/${id}.efkwgd`)).size>1000,id);
 assert.match(fs.readFileSync(path.join(root,'ptb-engine.js'),'utf8'),/ptbShowmotion\.paused/);
});
test('the effect-only asset server uses a random loopback route and rejects traversal',async()=>{
 const child=spawn(process.execPath,[path.join(root,'server.cjs')],{stdio:['pipe','pipe','pipe']});
 try{
  const [data]=await once(child.stdout,'data');const {url}=JSON.parse(data.toString());const address=new URL(url);
  assert.equal(address.hostname,'127.0.0.1');assert.match(address.pathname,/^\/[a-f0-9]{48}\/index\.html$/);
  const page=await fetch(url);assert.equal(page.status,200);assert.match(await page.text(),/ptb-engine\.js/);
  assert.equal((await fetch(new URL('/index.html',url))).status,404);
  assert.equal((await fetch(new URL('/'+address.pathname.split('/')[1]+'/%2e%2e%2fserver.cjs',url))).status,404);
 }finally{child.stdin.end();child.kill();}
});

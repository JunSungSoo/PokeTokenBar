// Read-only loopback asset server: WebGPU requires a trustworthy origin; no external binding.
const http=require('node:http'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=__dirname,token=crypto.randomBytes(24).toString('hex');
const mime={'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm','.json':'application/json','.wgsl':'text/plain','.wav':'audio/wav','.png':'image/png'};
const server=http.createServer((req,res)=>{
 let requested;try{requested=decodeURIComponent(new URL(req.url,'http://127.0.0.1').pathname);}catch{res.writeHead(400).end();return;}
 if(req.method!=='GET'||!requested.startsWith('/'+token+'/')){res.writeHead(404).end();return;}
 const file=path.resolve(root,requested.slice(token.length+2)||'index.html');
 if(!file.startsWith(root+path.sep)){res.writeHead(404).end();return;}
 fs.stat(file,(error,stat)=>{
  if(error||!stat.isFile()){res.writeHead(404).end();return;}
  res.writeHead(200,{'Content-Type':mime[path.extname(file)]||'application/octet-stream',
   'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
  fs.createReadStream(file).pipe(res);
 });
});
server.listen(0,'127.0.0.1',()=>process.stdout.write(JSON.stringify({url:`http://127.0.0.1:${server.address().port}/${token}/index.html`})+'\n'));
process.stdin.resume();process.stdin.on('end',()=>server.close());

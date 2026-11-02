// Public information only: no future opponent moves/items or unseen HP are features.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const {Dex}=require('../../BattleEngine/node_modules/pokemon-showdown'),{FEATURES,FEATURE_VERSION,features,LEAD_FEATURES,leadFeatures}=require('../../BattleEngine/challenge-policy.cjs');
const dex=Dex.mod('gen5'),directory=process.argv[2]||'build/challenge-training/raw',output=process.argv[3]||'build/challenge-training/examples.json';
const samples=[],leadSamples=[],games=[];let skipped=0;
for(const file of fs.readdirSync(directory).filter(n=>n.endsWith('.json')).sort()){
 const replay=JSON.parse(fs.readFileSync(path.join(directory,file))),lines=replay.log.split('\n').map(l=>l.split('|'));
 const teams=[[],[]],known=[new Map(),new Map()],prescan=[null,null];
 for(const p of lines){
  const side=p[2]?.startsWith('p1')?0:p[2]?.startsWith('p2')?1:-1;
  if(side<0)continue;
  if(p[1]==='poke')teams[side].push(p[3].split(',')[0]);
  if(['switch','drag','replace'].includes(p[1]))prescan[side]=p[3].split(',')[0];
  if(p[1]==='move'&&prescan[side]&&!p.slice(5).some(x=>x.startsWith('[from]'))){
   const move=dex.moves.get(p[3]);if(move.exists&&move.gen<=5){const set=known[side].get(prescan[side])||new Set();set.add(move.name);known[side].set(prescan[side],set);}
  }
 }
 if(lines.some(p=>p[1]==='move'&&dex.moves.get(p[3]).id==='transform')||teams.some(t=>t.length!==6||new Set(t).size!==6||t.some(s=>['zoroark','zorua','ditto'].includes(dex.species.get(s).id)))){skipped++;continue;}
 for(const side of [0,1]){
  const first=lines.find(p=>p[1]==='switch'&&p[2].startsWith('p'+(side+1)+'a'));
  const leader=first?.[3].split(',')[0],y=teams[side].indexOf(leader);
  if(y>=0)leadSamples.push({game:replay.id,x:teams[side].map(s=>leadFeatures(dex,s,teams[1-side].slice().sort())),y});
 }
 const members=teams.map(t=>new Map(t.map(s=>[s,{species:s,hp:1,status:'',boosts:{}}])));let active=[null,null],weather='',trickRoom=false,turn=0,start=null,chosen=[null,null],combat=false;
 const flush=()=>{
  if(!start)return;
  for(const side of [0,1]){
   const target=chosen[side],o=start[side];if(!target||!o||o.own.hp<=0||o.foe.hp<=0)continue;
   const moves=[...(known[side].get(o.own.species)||[])];if(moves.length<2||moves.length>4)continue;
   const actions=moves.map(move=>({kind:'move',move}));
   for(const mon of o.bench)actions.push({kind:'switch',species:mon.species,hp:mon.hp});
   const label=actions.findIndex(a=>a.kind===target.kind&&(a.kind==='move'?a.move===target.move:a.species===target.species));
   if(label<0||actions.length<2)continue;
   samples.push({game:replay.id,turn,side,x:actions.map(a=>features(dex,o,a)),y:label,action:target.kind});
  }
 };
 for(const p of lines){
  const side=p[2]?.startsWith('p1')?0:p[2]?.startsWith('p2')?1:-1;
  if(p[1]==='turn'){
   flush();turn=Number(p[2]);chosen=[null,null];combat=false;
   start=[0,1].map(i=>{
    const a=members[i].get(active[i]),b=members[1-i].get(active[1-i]);
    if(!a||!b)return null;
    return {own:structuredClone(a),foe:structuredClone(b),weather,trickRoom,ownSurvivors:[...members[i].values()].filter(p=>p.hp>0).length,foeSurvivors:[...members[1-i].values()].filter(p=>p.hp>0).length,bench:[...members[i].values()].filter(p=>p.species!==active[i]&&p.hp>0).map(p=>({...p}))};
   });continue;
  }
  if(p[1]==='-clearallboost'){for(const roster of members)for(const mon of roster.values())mon.boosts={};continue;}
  if(p[1]==='-weather'){weather=p[2]==='none'?'':p[2];continue;}
  if(['-fieldstart','-fieldend'].includes(p[1])&&p[2]==='move: Trick Room'){trickRoom=p[1]==='-fieldstart';continue;}
  if(side<0)continue;
  if(['switch','drag','replace'].includes(p[1])){
   const species=p[3].split(',')[0];
   if(p[1]==='switch'&&!combat&&start?.[side]?.own.hp>0&&!chosen[side]&&start[side].own.species!==species)chosen[side]={kind:'switch',species};
   active[side]=species;
   if(!members[side].has(species))members[side].set(species,{species,hp:1,status:'',boosts:{}});
   const mon=members[side].get(species);mon.boosts={};updateHP(mon,p[4]);
  }else{
   const mon=members[side].get(active[side]);if(!mon)continue;
   if(p[1]==='move')combat=true;
   if(p[1]==='move'&&!chosen[side]&&!p.slice(5).some(x=>x.startsWith('[from]')))chosen[side]={kind:'move',move:dex.moves.get(p[3]).name};
   if(['-damage','-heal'].includes(p[1]))updateHP(mon,p[3]);
   if(p[1]==='faint')mon.hp=0;
   if(p[1]==='-status')mon.status=p[3];if(p[1]==='-curestatus')mon.status='';
   if(['-boost','-unboost'].includes(p[1]))mon.boosts[p[3]]=Math.max(-6,Math.min(6,(mon.boosts[p[3]]||0)+Number(p[4])*(p[1]==='-boost'?1:-1)));
   if(p[1]==='-clearboost')mon.boosts={};
  }
 }
 flush();games.push({id:replay.id,source:replay.source,sha256:crypto.createHash('sha256').update(replay.log).digest('hex')});
}
function updateHP(mon,text=''){
 const m=/^(\d+)\/(\d+)/.exec(text);if(m)mon.hp=Number(m[1])/Number(m[2]);else if(text.startsWith('0'))mon.hp=0;
 const status=text.split(' ')[1];if(['brn','par','tox','psn','slp','frz'].includes(status))mon.status=status;
}
fs.writeFileSync(output,JSON.stringify({featureVersion:FEATURE_VERSION,features:FEATURES,leadFeatures:LEAD_FEATURES,leadSamples,games,samples,skipped}));
console.log(JSON.stringify({games:games.length,samples:samples.length,skipped,output}));

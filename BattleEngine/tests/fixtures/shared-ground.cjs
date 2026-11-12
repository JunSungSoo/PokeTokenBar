const {OwnedBattle}=require('../../engine.cjs');
const frames={};
function team(prefix){return ['Gyarados','Charizard','Raichu','Ampharos','Mew','Pidgey'].map((species,i)=>({id:prefix+i,species,ability:['Intimidate','Blaze','Static','Static','Synchronize','Keen Eye'][i],moves:['explosion','protect'],level:50,nature:'Hardy',ivs:{hp:31,atk:31,def:31,spa:31,spd:31,spe:31},stats:{hp:500,atk:120,def:150,spa:120,spd:150,spe:100}}));}
const open=resources=>new OwnedBattle('doubles',[team('a'),team('b')],[1,2,3,4],{profile:'challenge',resources});
const base=open();const state=base.frame(0).resources;for(let i=2;i<6;i++)state[i].hp=0;
for(const faint of [-1,0,1]){
 const e=open([state,null]);
 if(faint>=0){
  for(const player of [0,1]){const f=e.frame(player);e.choose(player,f.decisionID,[0,1].map(slot=>({kind:'move',index:player===0&&slot===faint?1:2,target:0})));}
 }
 const frame=e.frame(0);const name=faint<0?'large-pair':`survivor-${1-faint}`;
 frames[name]=frame;

}

process.stdout.write(JSON.stringify(frames));

const {OwnedBattle}=require('../../engine.cjs'),{Dex}=require('pokemon-showdown');
function team(p){return [['Charizard','charizarditex'],['Raichu','raichunitex'],['Gardevoir','gardevoirite'],['Blissey','sitrusberry'],['Slowbro','lumberry'],['Scizor','lifeorb']].map(([species,item],i)=>({id:p+i,species,item,ability:Dex.mod('gen5').species.get(species).abilities[0],moves:['tackle','splash'],level:50,nature:'Hardy',ivs:{hp:31,atk:31,def:31,spa:31,spd:31,spe:31},stats:{hp:500,atk:100,def:150,spa:100,spd:150,spe:100}}));}
const frames=[];
for(const mode of ['singles','doubles']){
 const e=new OwnedBattle(mode,[team('a'),team('b')],[1,2,3,4]);frames.push(e.frame(0));
 for(const p of [0,1]){
  const f=e.frame(p);e.choose(p,f.decisionID,Array.from({length:mode==='doubles'?2:1},(_,i)=>({kind:'move',index:1,target:1,mega:p===0 && i===(mode==='doubles'?1:0)})));
 }
 frames.push(e.frame(0));frames.push(e.frame(1));
}
process.stdout.write(JSON.stringify(frames));

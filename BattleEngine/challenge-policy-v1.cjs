'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const FEATURE_VERSION='bw-public-action-v1';
const FEATURES=['bias','switch','move','statusMove','power','effectiveness','stab','ownHP','foeHP','speed','priority','recovery','setup','hazard','statusInfliction','hazardRemoval','offense','switchRisk','switchHP','foeStatus','ownStatus','atkBoost','spaBoost','speBoost','sun','rain','trickRoom','ownSurvivors','foeSurvivors','recoveryNeed','setupSafety','boostedOffense'];
const recovery=new Set(['recover','roost','softboiled','slackoff','milkdrink','moonlight','morningsun','synthesis','rest','wish']);
const setup=new Set(['swordsdance','nastyplot','dragondance','calmmind','quiverdance','bulkup','curse','shellsmash','agility','rockpolish']);
function effectiveness(dex,type,types){return dex.getImmunity(type,types)?2**dex.getEffectiveness(type,types):0;}
function features(dex,o,c){
 const own=dex.species.get(o.own.species),foe=dex.species.get(o.foe.species),switching=c.kind==='switch';
 const move=switching?null:dex.moves.get(c.move),incoming=switching?dex.species.get(c.species):own;
 const types=o.foe.types||foe.types,ownTypes=o.own.types||own.types;
 const status=move?.category==='Status',power=(move?.basePower||0)/150;
 const eff=move&&!status?effectiveness(dex,move.type,types):0,stab=!!move&&ownTypes.includes(move.type);
 const hp=o.own.hp,fhp=o.foe.hp,boost=o.own.boosts||{};
 const risk=switching?Math.max(...types.map(t=>effectiveness(dex,t,incoming.types)))/4:0;
 const heal=!!move&&recovery.has(move.id),raise=!!move&&setup.has(move.id);
 const offense=power*eff*(stab?1.5:1);
 return [1,+switching,+!switching,+!!status,power,eff/4,+stab,hp,fhp,(incoming.baseStats.spe-foe.baseStats.spe)/150,(move?.priority||0)/7,+heal,+raise,+!!move&&['stealthrock','spikes','toxicspikes'].includes(move.id),+!!move&&!!move.status,+!!move&&['rapidspin','defog'].includes(move.id),offense,risk,switching?c.hp:0,+!!o.foe.status,+!!o.own.status,(boost.atk||0)/6,(boost.spa||0)/6,(boost.spe||0)/6,+['sunnyday','desolateland'].includes(o.weather),+['raindance','primordialsea'].includes(o.weather),+!!o.trickRoom,(o.ownSurvivors??6)/6,(o.foeSurvivors??6)/6,+heal*(1-hp),+raise*(hp-fhp),offense*((boost[move?.category==='Physical'?'atk':'spa']||0)/6)].map(Number);
}
const LEAD_FEATURES=['bias','hp','atk','def','spa','spd','spe','bestSTAB','averageRisk','maxRisk','normal','fire','water','electric','grass','ice','fighting','poison','ground','flying','psychic','bug','rock','ghost','dragon','dark','steel'];
function leadFeatures(dex,species,opponents){
 const own=dex.species.get(species),foes=opponents.map(s=>dex.species.get(s)),stats=own.baseStats;
 const offense=foes.map(f=>Math.max(...own.types.map(t=>effectiveness(dex,t,f.types))));
 const risks=foes.map(f=>Math.max(...f.types.map(t=>effectiveness(dex,t,own.types))));
 return [1,...['hp','atk','def','spa','spd','spe'].map(k=>stats[k]/150),offense.reduce((a,b)=>a+b,0)/Math.max(1,foes.length)/4,risks.reduce((a,b)=>a+b,0)/Math.max(1,foes.length)/4,Math.max(...risks)/4,...['Normal','Fire','Water','Electric','Grass','Ice','Fighting','Poison','Ground','Flying','Psychic','Bug','Rock','Ghost','Dragon','Dark','Steel'].map(t=>+own.types.includes(t))];
}
function chooseLead(dex,team,opponents,model=loadPolicy()){
 if(!model.lead||model.lead.weights.length!==LEAD_FEATURES.length)throw Error('Missing learned lead policy');
 const names=opponents.map(p=>p.species).sort(),scores=team.map(p=>leadFeatures(dex,p.species,names).reduce((v,x,i)=>v+x*model.lead.weights[i],0));
 return scores.indexOf(Math.max(...scores));
}
function candidates(frame){
 const slot=frame.slots[0];if(!slot||frame.waiting)return [];
 const list=[];
 if(!slot.mustSwitch&&!slot.canPass)for(const m of slot.moves)if(!m.disabled&&m.pp>0)list.push({kind:'move',index:m.index,move:m.name,target:0});
 if(slot.mustSwitch||!slot.trapped)frame.own.forEach((p,i)=>{if(!p.active&&!p.fainted)list.push({kind:'switch',index:i+1,species:p.name,hp:p.hp/p.maxHP,target:0});});
 if(!list.length&&slot.canPass)list.push({kind:'pass',index:0,target:0});
 return list;
}
function observation(frame){
 const own=frame.own.find(p=>p.active),foe=frame.foe[0];
 if(!own||!foe)return null;
 return {own:{species:own.name,hp:own.hp/own.maxHP,status:own.status,boosts:own.boosts},foe:{species:foe.name,hp:foe.hp/foe.maxHP,status:foe.status},weather:frame.field?.weather,trickRoom:frame.field?.conditions?.includes('trickroom'),ownSurvivors:frame.own.filter(p=>!p.fainted).length,foeSurvivors:6};
}
let cached;
function loadPolicy(){
 if(cached)return cached;
 const bytes=fs.readFileSync(path.join(__dirname,'challenge-policy-v1.json')),model=JSON.parse(bytes);
 if(model.featureVersion!==FEATURE_VERSION||JSON.stringify(model.features)!==JSON.stringify(FEATURES)||model.weights.length!==FEATURES.length||!model.weights.every(Number.isFinite))throw Error('Incompatible challenge policy');
 if(!model.lead||JSON.stringify(model.lead.features)!==JSON.stringify(LEAD_FEATURES)||model.lead.weights.length!==LEAD_FEATURES.length||!model.lead.weights.every(Number.isFinite))throw Error('Incompatible lead policy');
 return cached={...model,revision:crypto.createHash('sha256').update(bytes).digest('hex')};
}
function chooseCPU(dex,frame,model=loadPolicy()){
 let actions=candidates(frame);if(!actions.length)throw Error('No legal CPU action');
 // Explicit encounter tactic; this is not a retrained model. Legacy checkpoints lack
 // the field and continue using the unchanged learned scores for every action.
 const own=frame.own.find(p=>p.active),threshold=own?.cpuRecoveryThreshold;
 if(Number.isFinite(threshold)&&threshold>0&&threshold<1){
  const heal=actions.find(a=>a.kind==='move'&&dex.moves.get(a.move).id==='recover');
  if(heal&&own.hp/own.maxHP<=threshold)return {kind:heal.kind,index:heal.index,target:heal.target};
  if(own.hp===own.maxHP)actions=actions.filter(a=>a!==heal);
 }
 const o=observation(frame);let selected=actions[0],best=-Infinity;
 for(const action of actions){
  const vector=o&&action.kind!=='pass'?features(dex,o,action):FEATURES.map(()=>0);
  const score=vector.reduce((sum,x,i)=>sum+x*model.weights[i],0);
  if(score>best){best=score;selected=action;}
 }
 return {kind:selected.kind,index:selected.index,target:selected.target,...(selected.kind==='move'&&frame.slots[0]?.canMegaEvo?{mega:true}:{})};
}
module.exports={LEAD_FEATURES,leadFeatures,chooseLead,FEATURE_VERSION,FEATURES,features,observation,candidates,chooseCPU,loadPolicy};

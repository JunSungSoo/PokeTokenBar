#!/usr/bin/env python3
"""Small REINFORCE adaptation on this project's engine; keep the best validation model."""
import argparse,copy,hashlib,json,subprocess
from pathlib import Path
import numpy as np
p=argparse.ArgumentParser();p.add_argument('--batches',type=int,default=4);p.add_argument('--episodes',type=int,default=54);a=p.parse_args()
root=Path(__file__).resolve().parents[2];work=root/'build/challenge-training';work.mkdir(parents=True,exist_ok=True)
source=root/'BattleEngine/challenge-policy.json';initial=json.loads(source.read_text());current=copy.deepcopy(initial);best=copy.deepcopy(initial)
node=root/'BattleEngine/runtime/node';rollout=root/'scripts/challenge/rollouts.cjs';history=[]
def play(model,name,episodes,offset,shift,stochastic=False):
 weights=work/(name+'-weights.json');weights.write_text(json.dumps(model));output=work/(name+'.json')
 cmd=[str(node),str(rollout),'--weights',str(weights),'--episodes',str(episodes),'--offset',str(offset),'--pair-shift',str(shift),'--output',str(output)]
 if stochastic:cmd+=['--stochastic']
 subprocess.run(cmd,cwd=root,check=True,stdout=subprocess.DEVNULL)
 return json.loads(output.read_text())
validation=play(best,'validation-initial',27,2000,17)['metrics'];bestWins=validation['wins'];history.append({'initialValidation':validation})
for batch in range(a.batches):
 data=play(current,'adapt-'+str(batch),a.episodes,batch*a.episodes,13,True)
 weights=np.array(current['weights']);gradient=np.zeros_like(weights);count=0
 for trajectory in data['trajectories']:
  steps=trajectory['steps'];reward=trajectory['reward']
  for t,step in enumerate(steps):
   x=np.asarray(step['x'],dtype=float);scores=x@weights;scores-=scores.max();prob=np.exp(scores);prob/=prob.sum()
   advantage=reward*(.995**(len(steps)-1-t))
   gradient+=(x[step['y']]-prob@x)*advantage;count+=1
 if count:weights+=.35*gradient/count
 # Keep a small-sample update close to the behavior-cloned prior.
 weights-=.002*(weights-np.asarray(initial['weights']))
 current['weights']=weights.tolist();metrics=play(current,'validation-'+str(batch),27,2000,17)['metrics']
 history.append({'training':data['metrics'],'validation':metrics})
 if metrics['wins']>=bestWins:best=copy.deepcopy(current);bestWins=metrics['wins']
heldout=play(best,'heldout-final',54,4000,19)['metrics']
best['adaptation']={'method':'REINFORCE on bounded local engine rollouts, with regularization to the replay-trained policy','batches':a.batches,'trainingEpisodes':a.batches*a.episodes,'validationPairShift':17,'heldoutPairShift':19,'selectedBy':'validation wins; final heldout not used for selection','history':history,'heldout':heldout,'limitations':'Synthetic fixed roster matchups against a damage baseline; not human ladder performance, and not full HP/PP campaign optimization.'}
source.write_text(json.dumps(best,indent=2)+'\n')
(work/'adaptation-report.json').write_text(json.dumps(best['adaptation'],indent=2)+'\n')
print(json.dumps({'validationInitial':validation,'validationSelectedWins':bestWins,'heldout':heldout,'trainingEpisodes':a.batches*a.episodes},indent=2))

#!/usr/bin/env python3
"""Choose a conservative blend on development seeds; reserve fresh seeds for final audit."""
import copy,json,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[2];work=root/'build/challenge-training'
old=json.loads((root/'BattleEngine/challenge-policy-v1.json').read_text())
new=json.loads((work/'ai-review-warm-candidate.json').read_text())
prior=dict(zip(old['features'],old['weights']));prior['speciesSpeedPrior']=prior['speed'];prior['offensePrior']=prior['offense'];results=[];candidates=[]
for alpha in [.05,.1,.2,.35,.5]:
 model=copy.deepcopy(new)
 model['weights']=[(1-alpha)*prior.get(name,0)+alpha*weight for name,weight in zip(new['features'],new['weights'])]
 path=work/f'calibration-{alpha}.json';path.write_text(json.dumps(model))
 metrics=[]
 for offset,shift,count in [(2000,17,27),(4000,19,54)]:
  output=work/f'calibration-{alpha}-{offset}.json'
  subprocess.run([str(root/'BattleEngine/runtime/node'),str(root/'scripts/challenge/rollouts.cjs'),'--weights',str(path),'--episodes',str(count),'--offset',str(offset),'--pair-shift',str(shift),'--output',str(output)],cwd=root,check=True,stdout=subprocess.DEVNULL)
  metrics.append(json.loads(output.read_text())['metrics'])
 score=sum(m['wins']-.5*m['truncated'] for m in metrics)
 row={'alpha':alpha,'score':score,'development':metrics};results.append(row);candidates.append(model)
 print(json.dumps(row),flush=True)
best=max(range(len(results)),key=lambda i:results[i]['score']);model=candidates[best]
model['calibration']={'method':'Validation-selected convex blend with the prior replay/rollout-trained policy','selectedAlpha':results[best]['alpha'],'development':results,'note':'Both 2000 and previously published 4000 seeds are development data in this review. Final audit uses fresh 12000 seeds, never used for model selection.'}
(root/'BattleEngine/challenge-policy.json').write_text(json.dumps(model,indent=2)+'\n')

#!/usr/bin/env python3
"""Build a local, explicitly marked challenge QA app; never changes the release app."""
import pathlib,plistlib,shutil,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
subprocess.run(['swift','build','--arch','arm64'],cwd=root,check=True)
app=root/'build/PokeTokenBarChallengeTest.app';contents=app/'Contents'
if app.exists():shutil.rmtree(app)
(contents/'MacOS').mkdir(parents=True);resources=contents/'Resources';resources.mkdir()
shutil.copy2(root/'.build/arm64-apple-macosx/debug/PokeTokenBar',contents/'MacOS/PokeTokenBar')
shutil.copy2(root/'assets/AppIcon.icns',resources/'AppIcon.icns')
for name in ['BattleText','BattleEffects','Showmotion','PokeRogue','PokeRoguePlayer']:
 shutil.copytree(root/'Sources/PokeTokenBar/Resources'/name,resources/name)
engine=resources/'BattleEngine';engine.mkdir()
for pattern in ['*.cjs','*.json','*.wav']:
 for file in (root/'BattleEngine').glob(pattern):shutil.copy2(file,engine/file.name)
modules=engine/'node_modules';(modules/'pokemon-showdown/dist').mkdir(parents=True)
for name in ['sim','lib','data','config']:shutil.copytree(root/'BattleEngine/node_modules/pokemon-showdown/dist'/name,modules/'pokemon-showdown/dist'/name)
for name in ['package.json','LICENSE']:shutil.copy2(root/'BattleEngine/node_modules/pokemon-showdown'/name,modules/'pokemon-showdown'/name)
shutil.copytree(root/'BattleEngine/node_modules/ts-chacha20',modules/'ts-chacha20')
subprocess.run(['lipo',str(root/'BattleEngine/runtime/node'),'-thin','arm64','-output',str(engine/'node')],check=True)
(engine/'node').chmod(0o755)
info={'CFBundleExecutable':'PokeTokenBar','CFBundleIdentifier':'dev.poketokenbar.challengetest','CFBundleName':'PokeTokenBarChallengeTest','CFBundleDisplayName':'PokeTokenBar Challenge Test','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'2.5.6','CFBundleIconFile':'AppIcon','LSMinimumSystemVersion':'14.0','LSUIElement':True,'NSHighResolutionCapable':True,'PTBChallengeTestMode':True,'NSLocalNetworkUsageDescription':'Local Pokémon battle testing','NSBonjourServices':['_pokebattle._tcp','_poketrade._tcp']}
with (contents/'Info.plist').open('wb') as file:plistlib.dump(info,file)
subprocess.run(['codesign','--force','--sign','-',str(engine/'node')],check=True)
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
print(app)

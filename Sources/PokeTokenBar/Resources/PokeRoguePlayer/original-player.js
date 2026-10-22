var __defProp = Object.defineProperty;
var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
var __publicField = (obj, key, value) => __defNormalProp(obj, typeof key !== "symbol" ? key + "" : key, value);
const Phaser = window.Phaser;
let globalScene;
function bindScene(scene) {
  globalScene = scene;
}
const settings = { display: { enableMoveAnimations: true } };
const getFrameMs = (frames) => frames * 1e3 / 60;
const getEnumValues = (e) => Object.values(e).filter((v) => typeof v === "number");
const AnimFrameTarget = { USER: 0, TARGET: 1, GRAPHIC: 2 };
const AnimFocus = { TARGET: 1, USER: 2, USER_TARGET: 3, SCREEN: 4 };
const AnimBlendType = { NORMAL: 0, ADD: 1, SUBTRACT: 2 };
const BattlerTagType = { SUBSTITUTE: "substitute" };
const audioManager = { playSound: (key, config) => globalScene.sound.play(key, { ...config, volume: globalScene.audioEnabled ? config.volume : 0 }) };
class AnimConfig {
  constructor(source) {
    __publicField(this, "id");
    __publicField(this, "graphic");
    __publicField(this, "frames");
    __publicField(this, "frameTimedEvents");
    __publicField(this, "position");
    __publicField(this, "hue");
    this.frameTimedEvents = /* @__PURE__ */ new Map();
    if (source) {
      this.id = source.id;
      this.graphic = source.graphic;
      const frames = source.frames;
      frames.map((animFrames) => {
        for (let f = 0; f < animFrames.length; f++) {
          animFrames[f] = new ImportedAnimFrame(animFrames[f]);
        }
      });
      this.frames = frames;
      const frameTimedEvents = source.frameTimedEvents;
      for (const fte of Object.keys(frameTimedEvents)) {
        const timedEvents = [];
        for (const te of frameTimedEvents[fte]) {
          let timedEvent;
          switch (te.eventType) {
            case "AnimTimedSoundEvent":
              timedEvent = new AnimTimedSoundEvent(te.frameIndex, te.resourceName, te);
              break;
            case "AnimTimedAddBgEvent":
              timedEvent = new AnimTimedAddBgEvent(te.frameIndex, te.resourceName, te);
              break;
            case "AnimTimedUpdateBgEvent":
              timedEvent = new AnimTimedUpdateBgEvent(te.frameIndex, te.resourceName, te);
              break;
          }
          timedEvent && timedEvents.push(timedEvent);
        }
        this.frameTimedEvents.set(Number.parseInt(fte), timedEvents);
      }
      this.position = source.position;
      this.hue = source.hue;
    } else {
      this.frames = [];
    }
  }
  getSoundResourceNames() {
    const sounds = /* @__PURE__ */ new Set();
    for (const ftes of this.frameTimedEvents.values()) {
      for (const fte of ftes) {
        if (fte instanceof AnimTimedSoundEvent && fte.resourceName) {
          sounds.add(fte.resourceName);
        }
      }
    }
    return Array.from(sounds.values());
  }
  getBackgroundResourceNames() {
    const backgrounds = /* @__PURE__ */ new Set();
    for (const ftes of this.frameTimedEvents.values()) {
      for (const fte of ftes) {
        if (fte instanceof AnimTimedAddBgEvent && fte.resourceName) {
          backgrounds.add(fte.resourceName);
        }
      }
    }
    return Array.from(backgrounds.values());
  }
}
class AnimFrame {
  constructor(x, y, zoomX, zoomY, angle, mirror, visible, blendType, pattern, opacity, colorR, colorG, colorB, colorA, toneR, toneG, toneB, toneA, flashR, flashG, flashB, flashA, locked, priority, focus, init) {
    __publicField(this, "x");
    __publicField(this, "y");
    __publicField(this, "zoomX");
    __publicField(this, "zoomY");
    __publicField(this, "angle");
    __publicField(this, "mirror");
    __publicField(this, "visible");
    __publicField(this, "blendType");
    __publicField(this, "target");
    __publicField(this, "graphicFrame");
    __publicField(this, "opacity");
    __publicField(this, "color");
    __publicField(this, "tone");
    __publicField(this, "flash");
    __publicField(this, "locked");
    __publicField(this, "priority");
    __publicField(this, "focus");
    this.x = init ? x : ((x || 0) - 128) * 0.5;
    this.y = init ? y : ((y || 0) - 224) * 0.5;
    if (zoomX) {
      this.zoomX = zoomX;
    } else if (init) {
      this.zoomX = 0;
    }
    if (zoomY) {
      this.zoomY = zoomY;
    } else if (init) {
      this.zoomY = 0;
    }
    if (angle) {
      this.angle = angle;
    } else if (init) {
      this.angle = 0;
    }
    if (mirror) {
      this.mirror = mirror;
    } else if (init) {
      this.mirror = false;
    }
    if (visible) {
      this.visible = visible;
    } else if (init) {
      this.visible = false;
    }
    if (blendType) {
      this.blendType = blendType;
    } else if (init) {
      this.blendType = AnimBlendType.NORMAL;
    }
    if (!init) {
      let target = AnimFrameTarget.GRAPHIC;
      switch (pattern) {
        case -2:
          target = AnimFrameTarget.TARGET;
          break;
        case -1:
          target = AnimFrameTarget.USER;
          break;
      }
      this.target = target;
      this.graphicFrame = pattern >= 0 ? pattern : 0;
    }
    if (opacity) {
      this.opacity = opacity;
    } else if (init) {
      this.opacity = 0;
    }
    if (colorR || colorG || colorB || colorA) {
      this.color = [colorR || 0, colorG || 0, colorB || 0, colorA || 0];
    } else if (init) {
      this.color = [0, 0, 0, 0];
    }
    if (toneR || toneG || toneB || toneA) {
      this.tone = [toneR || 0, toneG || 0, toneB || 0, toneA || 0];
    } else if (init) {
      this.tone = [0, 0, 0, 0];
    }
    if (flashR || flashG || flashB || flashA) {
      this.flash = [flashR || 0, flashG || 0, flashB || 0, flashA || 0];
    } else if (init) {
      this.flash = [0, 0, 0, 0];
    }
    if (locked) {
      this.locked = locked;
    } else if (init) {
      this.locked = false;
    }
    if (priority) {
      this.priority = priority;
    } else if (init) {
      this.priority = 0;
    }
    this.focus = focus || AnimFocus.TARGET;
  }
}
class ImportedAnimFrame extends AnimFrame {
  constructor(source) {
    const color = source.color || [0, 0, 0, 0];
    const tone = source.tone || [0, 0, 0, 0];
    const flash = source.flash || [0, 0, 0, 0];
    super(
      source.x,
      source.y,
      source.zoomX,
      source.zoomY,
      source.angle,
      source.mirror,
      source.visible,
      source.blendType,
      source.graphicFrame,
      source.opacity,
      color[0],
      color[1],
      color[2],
      color[3],
      tone[0],
      tone[1],
      tone[2],
      tone[3],
      flash[0],
      flash[1],
      flash[2],
      flash[3],
      source.locked,
      source.priority,
      source.focus,
      true
    );
    this.target = source.target;
    this.graphicFrame = source.graphicFrame;
  }
}
class AnimTimedEvent {
  constructor(frameIndex, resourceName) {
    __publicField(this, "frameIndex");
    __publicField(this, "resourceName");
    this.frameIndex = frameIndex;
    this.resourceName = resourceName;
  }
}
class AnimTimedSoundEvent extends AnimTimedEvent {
  constructor(frameIndex, resourceName, source) {
    super(frameIndex, resourceName);
    __publicField(this, "volume", 100);
    __publicField(this, "pitch", 100);
    if (source) {
      this.volume = source.volume;
      this.pitch = source.pitch;
    }
  }
  execute(battleAnim) {
    const soundConfig = { rate: this.pitch * 0.01, volume: this.volume * 0.01 };
    if (this.resourceName) {
      try {
        audioManager.playSound(`battle_anims/${this.resourceName}`, soundConfig);
      } catch (err) {
        console.error(err);
      }
      const sound = globalScene.sound.get(`battle_anims/${this.resourceName}`);
      if (!sound) {
        return 0;
      }
      return Math.ceil(sound.totalDuration * 1e3 / 33.33);
    }
    const cry = battleAnim.user.cry(soundConfig);
    if (!cry) {
      return 0;
    }
    return Math.ceil(cry.totalDuration * 1e3 / 33.33);
  }
  getEventType() {
    return "AnimTimedSoundEvent";
  }
}
class AnimTimedBgEvent extends AnimTimedEvent {
  /*public flashScope: number = 0;
    public flashRed: number = 0;
    public flashGreen: number = 0;
    public flashBlue: number = 0;
    public flashAlpha: number = 0;
    public flashDuration: number = 0;*/
  constructor(frameIndex, resourceName, source) {
    super(frameIndex, resourceName);
    __publicField(this, "bgX", 0);
    __publicField(this, "bgY", 0);
    __publicField(this, "opacity", 0);
    /*public colorRed: number = 0;
      public colorGreen: number = 0;
      public colorBlue: number = 0;
      public colorAlpha: number = 0;*/
    __publicField(this, "duration", 0);
    if (source) {
      this.bgX = source.bgX;
      this.bgY = source.bgY;
      this.opacity = source.opacity;
      this.duration = source.duration;
    }
  }
}
class AnimTimedUpdateBgEvent extends AnimTimedBgEvent {
  // biome-ignore lint/correctness/noUnusedFunctionParameters: seems intentional
  execute(moveAnim, priority) {
    const tweenProps = {};
    if (this.bgX !== void 0) {
      tweenProps["x"] = this.bgX * 0.5 - 320;
    }
    if (this.bgY !== void 0) {
      tweenProps["y"] = this.bgY * 0.5 - 284;
    }
    if (this.opacity !== void 0) {
      tweenProps["alpha"] = (this.opacity || 0) / 255;
    }
    if (Object.keys(tweenProps).length > 0) {
      globalScene.tweens.add({
        targets: moveAnim.bgSprite,
        duration: getFrameMs(this.duration * 3),
        ...tweenProps
      });
    }
    return this.duration * 2;
  }
  getEventType() {
    return "AnimTimedUpdateBgEvent";
  }
}
class AnimTimedAddBgEvent extends AnimTimedBgEvent {
  execute(moveAnim, priority) {
    if (moveAnim.bgSprite) {
      moveAnim.bgSprite.destroy();
    }
    moveAnim.bgSprite = this.resourceName ? globalScene.add.tileSprite(this.bgX - 320, this.bgY - 284, 896, 576, this.resourceName) : globalScene.add.rectangle(this.bgX - 320, this.bgY - 284, 896, 576, 0);
    moveAnim.bgSprite.setOrigin(0, 0);
    moveAnim.bgSprite.setScale(1.25);
    moveAnim.bgSprite.setAlpha(this.opacity / 255);
    globalScene.field.add(moveAnim.bgSprite);
    const fieldPokemon = globalScene.getEnemyPokemon(false) ?? globalScene.getPlayerPokemon(false);
    if (priority != null) {
      globalScene.field.moveTo(moveAnim.bgSprite, priority);
    } else if (fieldPokemon?.isOnField()) {
      globalScene.field.moveBelow(moveAnim.bgSprite, fieldPokemon);
    }
    globalScene.tweens.add({
      targets: moveAnim.bgSprite,
      duration: getFrameMs(this.duration * 3)
    });
    return this.duration * 2;
  }
  getEventType() {
    return "AnimTimedAddBgEvent";
  }
}
const userFocusX = 106;
const userFocusY = 148 - 32;
const targetFocusX = 234;
const targetFocusY = 84 - 32;
function transformPoint(x1, y1, x2, y2, x3, y3, x4, y4, px, py) {
  const yIntersect = yAxisIntersect(x1, y1, x2, y2, px, py);
  return repositionY(x3, y3, x4, y4, yIntersect[0], yIntersect[1]);
}
function yAxisIntersect(x1, y1, x2, y2, px, py) {
  const dx = x2 - x1;
  const dy = y2 - y1;
  const x = dx === 0 ? 0 : (px - x1) / dx;
  const y = dy === 0 ? 0 : (py - y1) / dy;
  return [x, y];
}
function repositionY(x1, y1, x2, y2, tx, ty) {
  const dx = x2 - x1;
  const dy = y2 - y1;
  const x = x1 + tx * dx;
  const y = y1 + ty * dy;
  return [x, y];
}
function isReversed(src1, src2, dst1, dst2) {
  if (src1 === src2) {
    return false;
  }
  if (src1 < src2) {
    return dst1 > dst2;
  }
  return dst1 < dst2;
}
class BattleAnim {
  constructor(user, target, playRegardlessOfIssues = false) {
    __publicField(this, "user");
    __publicField(this, "target");
    __publicField(this, "sprites");
    __publicField(this, "bgSprite");
    /**
     * Will attempt to play as much of an animation as possible, even if not all targets are on the field.
     * Will also play the animation, even if the user has selected "Move Animations" OFF in Settings.
     * Exclusively used by MEs atm, for visual animations at the start of an encounter.
     */
    __publicField(this, "playRegardlessOfIssues");
    __publicField(this, "srcLine");
    __publicField(this, "dstLine");
    this.user = user ?? null;
    this.target = target ?? null;
    this.sprites = [];
    this.playRegardlessOfIssues = playRegardlessOfIssues;
  }
  isHideUser() {
    return false;
  }
  isHideTarget() {
    return false;
  }
  getGraphicFrameData(frames, onSubstitute) {
    const ret = /* @__PURE__ */ new Map([
      [AnimFrameTarget.GRAPHIC, /* @__PURE__ */ new Map()],
      [AnimFrameTarget.USER, /* @__PURE__ */ new Map()],
      [AnimFrameTarget.TARGET, /* @__PURE__ */ new Map()]
    ]);
    const isOppAnim = this.isOppAnim();
    const user = isOppAnim ? this.target : this.user;
    const target = isOppAnim ? this.user : this.target;
    const targetSubstitute = onSubstitute && user !== target ? target.getTag(BattlerTagType.SUBSTITUTE) : null;
    const userInitialX = user.x;
    const userInitialY = user.y;
    const userHalfHeight = user.getSprite().displayHeight / 2;
    const targetInitialX = targetSubstitute?.sprite?.x ?? target.x;
    const targetInitialY = targetSubstitute?.sprite?.y ?? target.y;
    const targetHalfHeight = (targetSubstitute?.sprite ?? target.getSprite()).displayHeight / 2;
    let g = 0;
    let u = 0;
    let t = 0;
    for (const frame of frames) {
      let x = frame.x + 106;
      let y = frame.y + 116;
      let scaleX = frame.zoomX / 100 * (frame.mirror ? -1 : 1);
      const scaleY = frame.zoomY / 100;
      switch (frame.focus) {
        case AnimFocus.TARGET:
          x += targetInitialX - targetFocusX;
          y += targetInitialY - targetHalfHeight - targetFocusY;
          break;
        case AnimFocus.USER:
          x += userInitialX - userFocusX;
          y += userInitialY - userHalfHeight - userFocusY;
          break;
        case AnimFocus.USER_TARGET:
          {
            const point = transformPoint(
              this.srcLine[0],
              this.srcLine[1],
              this.srcLine[2],
              this.srcLine[3],
              this.dstLine[0],
              this.dstLine[1] - userHalfHeight,
              this.dstLine[2],
              this.dstLine[3] - targetHalfHeight,
              x,
              y
            );
            x = point[0];
            y = point[1];
            if (frame.target === AnimFrameTarget.GRAPHIC && isReversed(this.srcLine[0], this.srcLine[2], this.dstLine[0], this.dstLine[2])) {
              scaleX *= -1;
            }
          }
          break;
      }
      const angle = -frame.angle;
      const key = frame.target === AnimFrameTarget.GRAPHIC ? g++ : frame.target === AnimFrameTarget.USER ? u++ : t++;
      ret.get(frame.target).set(key, { x, y, scaleX, scaleY, angle });
    }
    return ret;
  }
  // TODO: Make this async
  play(onSubstitute, callback) {
    const isOppAnim = this.isOppAnim();
    const user = isOppAnim ? this.target : this.user;
    const target = isOppAnim ? this.user : this.target;
    if (!target?.isOnField() && !this.playRegardlessOfIssues) {
      if (callback) {
        callback();
      }
      return;
    }
    const targetSubstitute = onSubstitute && user !== target ? target.getTag(BattlerTagType.SUBSTITUTE) : null;
    const userSprite = user.getSprite();
    const targetSprite = targetSubstitute?.sprite ?? target.getSprite();
    const spriteCache = {
      [AnimFrameTarget.GRAPHIC]: [],
      [AnimFrameTarget.USER]: [],
      [AnimFrameTarget.TARGET]: []
    };
    const spritePriorities = [];
    const cleanUpAndComplete = () => {
      userSprite.setPosition(0, 0);
      userSprite.setScale(1);
      userSprite.setAlpha(1);
      userSprite.pipelineData["tone"] = [0, 0, 0, 0];
      userSprite.setAngle(0);
      if (targetSubstitute) {
        targetSprite.setPosition(
          target.x - target.getSubstituteOffset()[0],
          target.y - target.getSubstituteOffset()[1]
        );
        targetSprite.setScale(target.getSpriteScale() * (target.isPlayer() ? 0.5 : 1));
        targetSprite.setAlpha(1);
      } else {
        targetSprite.setPosition(0, 0);
        targetSprite.setScale(1);
        targetSprite.setAlpha(1);
      }
      targetSprite.pipelineData["tone"] = [0, 0, 0, 0];
      targetSprite.setAngle(0);
      userSprite.off("animationupdate");
      targetSprite.off("animationupdate");
      const userSpriteToShow = isOppAnim ? targetSprite : userSprite;
      const targetSpriteToShow = isOppAnim ? userSprite : targetSprite;
      if (!this.isHideUser() && userSpriteToShow) {
        userSpriteToShow.setVisible(true);
      }
      if (!this.isHideTarget() && (targetSpriteToShow !== userSpriteToShow || !this.isHideUser())) {
        targetSpriteToShow.setVisible(true);
      }
      for (const ms of Object.values(spriteCache).flat()) {
        if (ms) {
          ms.destroy();
        }
      }
      if (this.bgSprite) {
        this.bgSprite.destroy();
      }
      if (callback) {
        callback();
      }
    };
    if (!settings.display.enableMoveAnimations && !this.playRegardlessOfIssues) {
      return cleanUpAndComplete();
    }
    const anim = this.getAnim();
    const userInitialX = user.x;
    const userInitialY = user.y;
    const targetInitialX = targetSubstitute?.sprite?.x ?? target.x;
    const targetInitialY = targetSubstitute?.sprite?.y ?? target.y;
    this.srcLine = [userFocusX, userFocusY, targetFocusX, targetFocusY];
    this.dstLine = [userInitialX, userInitialY, targetInitialX, targetInitialY];
    let r = anim?.frames.length ?? 0;
    let f = 0;
    globalScene.tweens.addCounter({
      duration: getFrameMs(3),
      repeat: anim?.frames.length ?? 0,
      onRepeat: () => {
        if (!f) {
          userSprite.setVisible(false);
          targetSprite.setVisible(false);
        }
        const spriteFrames = anim.frames[f];
        const frameData = this.getGraphicFrameData(anim.frames[f], onSubstitute);
        let u = 0;
        let t = 0;
        let g = 0;
        for (const frame of spriteFrames) {
          if (frame.target === AnimFrameTarget.GRAPHIC) {
            const sprites = spriteCache[AnimFrameTarget.GRAPHIC];
            if (g === sprites.length) {
              const newSprite = globalScene.addFieldSprite(0, 0, anim.graphic, 1);
              sprites.push(newSprite);
              globalScene.field.add(newSprite);
              spritePriorities.push(1);
            }
            const graphicIndex = g++;
            const moveSprite = sprites[graphicIndex];
            if (spritePriorities[graphicIndex] !== frame.priority) {
              spritePriorities[graphicIndex] = frame.priority;
              const setSpritePriority = (priority) => {
                let targetSprite2;
                let moveFunc = globalScene.field.bringToTop;
                if (priority === 0) {
                  targetSprite2 = globalScene.getEnemyField().find((p) => p) ?? globalScene.getPlayerField().find((p) => p);
                  moveFunc = globalScene.field.moveBelow;
                } else if (priority === 2 && this.bgSprite) {
                  moveFunc = globalScene.field.moveAbove;
                  targetSprite2 = this.bgSprite;
                } else if (priority === 2 || priority === 3) {
                  moveFunc = priority === 2 ? globalScene.field.moveBelow : globalScene.field.moveAbove;
                  if (frame.focus === AnimFocus.USER) {
                    targetSprite2 = this.user;
                  } else if (frame.focus === AnimFocus.TARGET) {
                    targetSprite2 = this.target;
                  }
                }
                targetSprite2 && globalScene.field.exists(targetSprite2) ? moveFunc.bind(globalScene.field)(moveSprite, targetSprite2) : globalScene.field.bringToTop(moveSprite);
              };
              setSpritePriority(frame.priority);
            }
            moveSprite.setFrame(frame.graphicFrame);
            const graphicFrameData = frameData.get(frame.target).get(graphicIndex);
            moveSprite.setPosition(graphicFrameData.x, graphicFrameData.y);
            moveSprite.setAngle(graphicFrameData.angle);
            moveSprite.setScale(graphicFrameData.scaleX, graphicFrameData.scaleY);
            moveSprite.setAlpha(frame.opacity / 255);
            moveSprite.setVisible(frame.visible);
            moveSprite.setBlendMode(
              frame.blendType === AnimBlendType.NORMAL ? Phaser.BlendModes.NORMAL : frame.blendType === AnimBlendType.ADD ? Phaser.BlendModes.ADD : Phaser.BlendModes.DIFFERENCE
            );
          } else {
            const isUser = frame.target === AnimFrameTarget.USER;
            if (isUser && target === user) {
              continue;
            }
            if (this.playRegardlessOfIssues && frame.target === AnimFrameTarget.TARGET && !target.isOnField()) {
              continue;
            }
            const sprites = spriteCache[isUser ? AnimFrameTarget.USER : AnimFrameTarget.TARGET];
            const spriteSource = isUser ? userSprite : targetSprite;
            if ((isUser ? u : t) === sprites.length) {
              if (isUser || !targetSubstitute) {
                const sprite = globalScene.addPokemonSprite(
                  isUser ? user : target,
                  0,
                  0,
                  spriteSource.texture,
                  spriteSource.frame.name,
                  true
                );
                ["spriteColors", "fusionSpriteColors"].map(
                  (k) => sprite.pipelineData[k] = (isUser ? user : target).getSprite().pipelineData[k]
                );
                sprite.setPipelineData("spriteKey", (isUser ? user : target).getBattleSpriteKey());
                sprite.setPipelineData("shiny", (isUser ? user : target).shiny);
                sprite.setPipelineData("variant", (isUser ? user : target).variant);
                sprite.setPipelineData("ignoreFieldPos", true);
                spriteSource.on("animationupdate", (_anim, frame2) => sprite.setFrame(frame2.textureFrame));
                globalScene.field.add(sprite);
                sprites.push(sprite);
              } else {
                const sprite = globalScene.addFieldSprite(spriteSource.x, spriteSource.y, spriteSource.texture);
                spriteSource.on("animationupdate", (_anim, frame2) => sprite.setFrame(frame2.textureFrame));
                globalScene.field.add(sprite);
                sprites.push(sprite);
              }
            }
            const spriteIndex = isUser ? u++ : t++;
            const pokemonSprite = sprites[spriteIndex];
            const graphicFrameData = frameData.get(frame.target).get(spriteIndex);
            const spriteSourceScale = isUser || !targetSubstitute ? spriteSource.parentContainer.scale : target.getSpriteScale() * (target.isPlayer() ? 0.5 : 1);
            pokemonSprite.setPosition(
              graphicFrameData.x,
              graphicFrameData.y - spriteSource.height / 2 * (spriteSourceScale - 1)
            );
            pokemonSprite.setAngle(graphicFrameData.angle);
            pokemonSprite.setScale(
              graphicFrameData.scaleX * spriteSourceScale,
              graphicFrameData.scaleY * spriteSourceScale
            );
            pokemonSprite.setData("locked", frame.locked);
            pokemonSprite.setAlpha(frame.opacity / 255);
            pokemonSprite.pipelineData["tone"] = frame.tone;
            pokemonSprite.setVisible(frame.visible && (isUser ? user.visible : target.visible));
            pokemonSprite.setBlendMode(
              frame.blendType === AnimBlendType.NORMAL ? Phaser.BlendModes.NORMAL : frame.blendType === AnimBlendType.ADD ? Phaser.BlendModes.ADD : Phaser.BlendModes.DIFFERENCE
            );
          }
        }
        if (anim?.frameTimedEvents.has(f)) {
          const base = anim.frames.length - f;
          for (const event of anim.frameTimedEvents.get(f)) {
            r = Math.max(base + event.execute(this), r);
          }
        }
        const targets = getEnumValues(AnimFrameTarget);
        for (const i of targets) {
          const count = i === AnimFrameTarget.GRAPHIC ? g : i === AnimFrameTarget.USER ? u : t;
          if (count < spriteCache[i].length) {
            const spritesToRemove = spriteCache[i].slice(count, spriteCache[i].length);
            for (const rs of spritesToRemove) {
              if (!rs.getData("locked")) {
                const spriteCacheIndex = spriteCache[i].indexOf(rs);
                spriteCache[i].splice(spriteCacheIndex, 1);
                if (i === AnimFrameTarget.GRAPHIC) {
                  spritePriorities.splice(spriteCacheIndex, 1);
                }
                rs.destroy();
              }
            }
          }
        }
        f++;
        r--;
      },
      onComplete: () => {
        for (const ms of Object.values(spriteCache).flat()) {
          if (ms && !ms.getData("locked")) {
            ms.destroy();
          }
        }
        if (r) {
          globalScene.tweens.addCounter({
            duration: getFrameMs(r),
            onComplete: () => cleanUpAndComplete()
          });
        } else {
          cleanUpAndComplete();
        }
      }
    });
  }
  getGraphicFrameDataWithoutTarget(frames, targetInitialX, targetInitialY) {
    const ret = /* @__PURE__ */ new Map([
      [AnimFrameTarget.GRAPHIC, /* @__PURE__ */ new Map()],
      [AnimFrameTarget.USER, /* @__PURE__ */ new Map()],
      [AnimFrameTarget.TARGET, /* @__PURE__ */ new Map()]
    ]);
    let g = 0;
    let u = 0;
    let t = 0;
    for (const frame of frames) {
      let { x, y } = frame;
      const scaleX = frame.zoomX / 100 * (frame.mirror ? -1 : 1);
      const scaleY = frame.zoomY / 100;
      x += targetInitialX;
      y += targetInitialY;
      const angle = -frame.angle;
      const key = frame.target === AnimFrameTarget.GRAPHIC ? g++ : frame.target === AnimFrameTarget.USER ? u++ : t++;
      ret.get(frame.target)?.set(key, {
        x,
        y,
        scaleX,
        scaleY,
        angle
      });
    }
    return ret;
  }
  /**
   * @param targetInitialX
   * @param targetInitialY
   * @param frameTimeMult
   * @param frameTimedEventPriority
   * - 0 is behind all other sprites (except BG)
   * - 1 on top of player field
   * - 3 is on top of both fields
   * - 5 is on top of player sprite
   * @param callback
   */
  playWithoutTargets(targetInitialX, targetInitialY, frameTimeMult, frameTimedEventPriority, callback) {
    const spriteCache = {
      [AnimFrameTarget.GRAPHIC]: [],
      [AnimFrameTarget.USER]: [],
      [AnimFrameTarget.TARGET]: []
    };
    const cleanUpAndComplete = () => {
      for (const ms of Object.values(spriteCache).flat()) {
        if (ms) {
          ms.destroy();
        }
      }
      if (this.bgSprite) {
        this.bgSprite.destroy();
      }
      if (callback) {
        callback();
      }
    };
    if (!settings.display.enableMoveAnimations && !this.playRegardlessOfIssues) {
      return cleanUpAndComplete();
    }
    const anim = this.getAnim();
    this.srcLine = [userFocusX, userFocusY, targetFocusX, targetFocusY];
    this.dstLine = [150, 75, targetInitialX, targetInitialY];
    let totalFrames = anim.frames.length;
    let frameCount = 0;
    let existingFieldSprites = globalScene.field.getAll().slice(0);
    globalScene.tweens.addCounter({
      duration: getFrameMs(3) * frameTimeMult,
      repeat: anim.frames.length,
      onRepeat: () => {
        existingFieldSprites = globalScene.field.getAll().slice(0);
        const spriteFrames = anim.frames[frameCount];
        const frameData = this.getGraphicFrameDataWithoutTarget(
          anim.frames[frameCount],
          targetInitialX,
          targetInitialY
        );
        let graphicFrameCount = 0;
        for (const frame of spriteFrames) {
          if (frame.target !== AnimFrameTarget.GRAPHIC) {
            console.log("Encounter animations do not support targets");
            continue;
          }
          const sprites = spriteCache[AnimFrameTarget.GRAPHIC];
          if (graphicFrameCount === sprites.length) {
            const newSprite = globalScene.addFieldSprite(0, 0, anim.graphic, 1);
            sprites.push(newSprite);
            globalScene.field.add(newSprite);
          }
          const graphicIndex = graphicFrameCount++;
          const moveSprite = sprites[graphicIndex];
          if (frame.priority != null) {
            const setSpritePriority = (priority) => {
              if (existingFieldSprites.length > priority) {
                const index = globalScene.field.getIndex(existingFieldSprites[priority]);
                globalScene.field.moveTo(moveSprite, index);
              } else {
                globalScene.field.moveTo(moveSprite, globalScene.field.getAll().length - 1);
              }
            };
            setSpritePriority(frame.priority);
          }
          moveSprite.setFrame(frame.graphicFrame);
          const graphicFrameData = frameData.get(frame.target)?.get(graphicIndex);
          if (graphicFrameData) {
            moveSprite.setPosition(graphicFrameData.x, graphicFrameData.y);
            moveSprite.setAngle(graphicFrameData.angle);
            moveSprite.setScale(graphicFrameData.scaleX, graphicFrameData.scaleY);
            moveSprite.setAlpha(frame.opacity / 255);
            moveSprite.setVisible(frame.visible);
            moveSprite.setBlendMode(
              frame.blendType === AnimBlendType.NORMAL ? Phaser.BlendModes.NORMAL : frame.blendType === AnimBlendType.ADD ? Phaser.BlendModes.ADD : Phaser.BlendModes.DIFFERENCE
            );
          }
        }
        if (anim?.frameTimedEvents.get(frameCount)) {
          const base = anim.frames.length - frameCount;
          for (const event of anim.frameTimedEvents.get(frameCount)) {
            totalFrames = Math.max(base + event.execute(this, frameTimedEventPriority), totalFrames);
          }
        }
        const targets = getEnumValues(AnimFrameTarget);
        for (const i of targets) {
          const count = graphicFrameCount;
          if (count < spriteCache[i].length) {
            const spritesToRemove = spriteCache[i].slice(count, spriteCache[i].length);
            for (const sprite of spritesToRemove) {
              if (!sprite.getData("locked")) {
                const spriteCacheIndex = spriteCache[i].indexOf(sprite);
                spriteCache[i].splice(spriteCacheIndex, 1);
                sprite.destroy();
              }
            }
          }
        }
        frameCount++;
        totalFrames--;
      },
      onComplete: () => {
        for (const sprite of Object.values(spriteCache).flat()) {
          if (sprite && !sprite.getData("locked")) {
            sprite.destroy();
          }
        }
        if (totalFrames) {
          globalScene.tweens.addCounter({
            duration: getFrameMs(totalFrames),
            onComplete: () => cleanUpAndComplete()
          });
        } else {
          cleanUpAndComplete();
        }
      }
    });
  }
}
export {
  AnimConfig,
  BattleAnim,
  bindScene,
  globalScene
};

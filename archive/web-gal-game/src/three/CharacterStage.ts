import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { MMDLoader, MMDMaterialPlugin, type MMD as MmdModel } from '@moeru/three-mmd';
import { MMDPhysicalMaterial } from '@moeru/three-mmd/materials/physical';

export interface MorphInfo {
  mesh: string;
  targets: string[];
}

export interface StageDiagnostics {
  height: number;
  width: number;
  bones: number;
  meshes: number;
  materials: number;
  animations: number;
  morphs: MorphInfo[];
  pose: Record<string, unknown>;
}

export type ModelType = 'glb' | 'pmx';

export interface StageOptions {
  url: string;
  type?: ModelType;
  /** Directory used to resolve PMX textures (must end with a slash). */
  resourcePath?: string;
  /** The model is scaled so its bounding-box height matches this value. */
  targetHeight?: number;
  /** Rotate the model 180° around Y. PMX handedness sometimes needs it. */
  flip?: boolean;
  armAngle?: number;
  forearmAngle?: number;
  materialMode?: 'toon' | 'physical';
  onProgress?: (ratio: number) => void;
}

type BoneOffset = [number, number, number];

/** three.js sanitizes node names: "腕.L" becomes "腕L". Match both. */
function normalizeBoneName(name: string): string {
  return name.replace(/[.\s_:/\[\]]/g, '');
}

/**
 * GLB and PMX use different naming conventions.
 * GLB: 腕.L / 腕捩.L / ひじ.L / 手捩.L
 * PMX: 左腕 / 左腕捩 / 左ひじ / 左手首
 */
const BONE_SYNONYMS: Record<string, string[]> = {
  '腕.L': ['腕.L', '左腕'],
  '腕.R': ['腕.R', '右腕'],
  '腕捩.L': ['腕捩.L', '左腕捩'],
  '腕捩.R': ['腕捩.R', '右腕捩'],
  'ひじ.L': ['ひじ.L', '左ひじ'],
  'ひじ.R': ['ひじ.R', '右ひじ'],
  '手捩.L': ['手捩.L', '左手首'],
  '手捩.R': ['手捩.R', '右手首'],
};

/**
 * Owns the three.js scene. The Vue component is only a canvas host; all
 * animation/audio logic lives here so it can be tested independently.
 */
export class CharacterStage {
  private readonly canvas: HTMLCanvasElement;
  private readonly renderer: THREE.WebGLRenderer;
  private readonly scene = new THREE.Scene();
  private readonly camera: THREE.PerspectiveCamera;
  private readonly clock = new THREE.Clock();

  private model: THREE.Object3D | null = null;
  private mmd: MmdModel | null = null;
  private bones = new Map<string, THREE.Bone>();
  private boneAliases = new Map<string, THREE.Bone>();
  private restQuats = new Map<string, THREE.Quaternion>();
  private baseQuats = new Map<string, THREE.Quaternion>();
  private baseOffsets: Record<string, BoneOffset> = {};
  private armAngle = 12;
  private forearmAngle = 38;
  private armParamSet = false;
  private expressionEnabled = true;
  private materialMode: 'toon' | 'physical' = 'toon';
  private materialParamSet = false;
  private mouthOverride: number | null = null;

  private mouth: { mesh: THREE.Mesh; index: Record<string, number> } | null = null;
  private blink: { mesh: THREE.Mesh; index: number } | null = null;
  private expressionMeshes: Array<{ mesh: THREE.Mesh; index: Record<string, number> }> = [];

  private analyser: AnalyserNode | null = null;
  private waveData: Uint8Array<ArrayBuffer> | null = null;
  private speaking = false;
  private energy = 0;

  private pointer = new THREE.Vector2();
  private pointerSmooth = new THREE.Vector2();
  private cameraBase = new THREE.Vector3(0.1, 1.28, 2.6);
  private lookAtBase = new THREE.Vector3(0.3, 1.1, 0);
  private modelBaseX = 0;
  private blinkCooldown = 2.2;
  private blinkRemaining = 0;
  private readonly blinkDuration = 0.16;

  private raf = 0;
  private disposed = false;
  private resizeObserver: ResizeObserver | null = null;

  diagnostics: StageDiagnostics | null = null;
  private poseDebug: Record<string, unknown> = {};

  constructor(canvas: HTMLCanvasElement) {
    this.canvas = canvas;
    const params = new URLSearchParams(window.location.search);
    if (params.has('arm')) {
      this.armAngle = Number(params.get('arm')) || 0;
      this.armParamSet = true;
    }
    if (params.has('forearm')) {
      this.forearmAngle = Number(params.get('forearm')) || 0;
      this.armParamSet = true;
    }
    if (params.get('expr') === '0') this.expressionEnabled = false;
    const materialParam = params.get('mat');
    if (materialParam === 'physical' || materialParam === 'toon') {
      this.materialMode = materialParam;
      this.materialParamSet = true;
    }
    const mouthParam = params.get('mouth');
    if (mouthParam !== null && mouthParam !== '') {
      this.mouthOverride = Math.max(0, Math.min(1, Number(mouthParam)));
    }
    this.renderer = new THREE.WebGLRenderer({
      canvas,
      alpha: true,
      antialias: true,
      powerPreference: 'high-performance',
    });
    this.renderer.setClearColor(0x000000, 0);
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 0.86;
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));

    this.camera = new THREE.PerspectiveCamera(30, 1, 0.05, 40);
    this.camera.position.copy(this.cameraBase);

    this.scene.add(new THREE.HemisphereLight(0xfff1e0, 0x1a2234, 1.0));
    const key = new THREE.DirectionalLight(0xffe4c4, 1.5);
    key.position.set(1.4, 2.6, 2.4);
    this.scene.add(key);
    const fill = new THREE.DirectionalLight(0xffd6e2, 0.45);
    fill.position.set(-1.6, 1.2, 1.8);
    this.scene.add(fill);
    const rim = new THREE.DirectionalLight(0x8fb8ff, 1.3);
    rim.position.set(-1.2, 2.0, -2.2);
    this.scene.add(rim);

    const pmrem = new THREE.PMREMGenerator(this.renderer);
    this.scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.05).texture;
    this.scene.environmentIntensity = 0.22;
    pmrem.dispose();

    this.resize();
    this.resizeObserver = new ResizeObserver(() => this.resize());
    this.resizeObserver.observe(canvas.parentElement ?? canvas);

    window.addEventListener('pointermove', this.onPointerMove, { passive: true });
    this.loop();
  }

  async load(options: StageOptions): Promise<StageDiagnostics> {
    if (!this.armParamSet) {
      if (options.armAngle !== undefined) this.armAngle = options.armAngle;
      if (options.forearmAngle !== undefined) this.forearmAngle = options.forearmAngle;
    }
    if (!this.materialParamSet && options.materialMode) {
      this.materialMode = options.materialMode;
    }
    options.onProgress?.(0.06);
    if ((options.type ?? 'glb') === 'pmx') return this.loadPmx(options);
    return this.loadGlb(options);
  }

  private async loadGlb(options: StageOptions): Promise<StageDiagnostics> {
    const loader = new GLTFLoader();
    const gltf = await loader.loadAsync(options.url, (event) => {
      if (options.onProgress && event.total > 0) {
        options.onProgress(Math.min(0.8, (event.loaded / event.total) * 0.8));
      }
    });
    return this.finalize(gltf.scene, gltf.animations.length, options, 'glb');
  }

  private async loadPmx(options: StageOptions): Promise<StageDiagnostics> {
    const loader = new MMDLoader();
    if (this.materialMode === 'physical') {
      loader.register(
        (parser) =>
          new MMDMaterialPlugin(parser, {
            materialType: MMDPhysicalMaterial,
          }),
      );
    }
    const resourcePath =
      options.resourcePath ?? options.url.slice(0, options.url.lastIndexOf('/') + 1);
    if (resourcePath) loader.setResourcePath(resourcePath);

    const mmd = await loader.loadAsync(options.url, (event) => {
      if (options.onProgress && event.total > 0) {
        options.onProgress(Math.min(0.75, (event.loaded / event.total) * 0.75));
      }
    });
    this.mmd = mmd;

    // Scale/position the wrapper, not the SkinnedMesh, so MMD's own transforms
    // (and any future physics service) keep working in mesh space.
    const root = new THREE.Group();
    root.name = 'mmd-root';
    root.add(mmd.mesh);
    return this.finalize(root, 0, options, 'pmx');
  }

  private finalize(
    root: THREE.Object3D,
    animationCount: number,
    options: StageOptions,
    type: ModelType,
  ): StageDiagnostics {
    this.bones.clear();
    this.boneAliases.clear();
    this.restQuats.clear();
    this.baseQuats.clear();
    this.expressionMeshes = [];
    this.mouth = null;
    this.blink = null;

    let meshCount = 0;
    let materialCount = 0;
    const morphs: MorphInfo[] = [];
    const materialNames: string[] = [];

    root.traverse((object) => {
      const mesh = object as THREE.Mesh;
      if (mesh.isMesh) {
        meshCount += 1;
        mesh.frustumCulled = false;
        const materials = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
        materialCount += materials.length;
        for (const material of materials) {
          const m = material as THREE.Material & {
            map?: THREE.Texture;
            transparent?: boolean;
          };
          materialNames.push(m.name);
          if (m.map) m.map.colorSpace = THREE.SRGBColorSpace;
          // GLB rips use BLEND everywhere; alphaTest avoids sorting artifacts.
          // PMX materials manage alpha/outline themselves; leave them alone.
          if (type === 'glb' && m.transparent) {
            (m as THREE.MeshStandardMaterial).alphaTest = 0.04;
          }
          m.needsUpdate = true;
        }

        const dict = mesh.morphTargetDictionary;
        if (dict) {
          const keys = Object.keys(dict);
          this.expressionMeshes.push({ mesh, index: dict });
          morphs.push({ mesh: mesh.name, targets: keys });
          if (keys.includes('あ') && keys.includes('い') && keys.includes('う')) {
            this.mouth = { mesh, index: dict };
          }
          if (keys.includes('まばたき')) {
            this.blink = { mesh, index: dict['まばたき'] };
          }
        }
      }
      if ((object as THREE.Bone).isBone) {
        const bone = object as THREE.Bone;
        this.bones.set(bone.name, bone);
        this.boneAliases.set(normalizeBoneName(bone.name), bone);
        this.restQuats.set(bone.uuid, bone.quaternion.clone());
      }
    });

    if (options.flip) root.rotation.y = Math.PI;

    let box = new THREE.Box3().setFromObject(root);
    let size = box.getSize(new THREE.Vector3());
    const targetHeight = options.targetHeight ?? 1.576;
    if (size.y > 1e-4) {
      root.scale.multiplyScalar(targetHeight / size.y);
    }

    box = new THREE.Box3().setFromObject(root);
    size = box.getSize(new THREE.Vector3());
    const center = box.getCenter(new THREE.Vector3());
    root.position.x -= center.x;
    root.position.z -= center.z;
    root.position.y -= box.min.y;

    this.model = root;
    this.modelBaseX = root.position.x;
    this.scene.add(root);
    this.setLayout();

    if (this.expressionEnabled) {
      this.setExpression('にっこり', 0.18);
      this.setExpression('にこり', 0.2);
      this.setExpression('なごみ', 0.2);
    }

    this.poseDebug.modelType = type;
    this.poseDebug.materialMode = this.materialMode;
    this.poseDebug.materialNames = materialNames;
    this.poseDebug.expressionEnabled = this.expressionEnabled;
    this.poseDebug.hasArmL = Boolean(this.findBone('腕.L'));
    this.poseDebug.hasElbowL = Boolean(this.findBone('腕捩.L'));
    this.poseDebug.armBones = [...this.bones.keys()].filter((k) => k.includes('腕')).slice(0, 16);
    this.poseDebug.boneSample = [...this.bones.keys()].slice(0, 12);
    this.poseDebug.armAngle = this.armAngle;
    this.poseDebug.forearmAngle = this.forearmAngle;
    this.poseDebug.flip = Boolean(options.flip);
    this.applyBasePose();
    options.onProgress?.(0.85);

    this.diagnostics = {
      height: Number(size.y.toFixed(3)),
      width: Number(size.x.toFixed(3)),
      bones: this.bones.size,
      meshes: meshCount,
      materials: materialCount,
      animations: animationCount,
      morphs,
      pose: this.poseDebug,
    };
    return this.diagnostics;
  }

  /** Tune the idle pose without rebuilding the app. */
  setBoneOffset(name: string, offset: BoneOffset | null) {
    if (offset) {
      this.baseOffsets[name] = offset;
    } else {
      delete this.baseOffsets[name];
    }
    this.applyBasePose();
  }

  setExpression(name: string, weight: number) {
    for (const entry of this.expressionMeshes) {
      const index = entry.index[name];
      if (index !== undefined && entry.mesh.morphTargetInfluences) {
        entry.mesh.morphTargetInfluences[index] = weight;
      }
    }
  }

  setArmPose(armAngle: number, forearmAngle: number) {
    this.armAngle = armAngle;
    this.forearmAngle = forearmAngle;
    this.applyBasePose();
  }

  private findBone(name: string): THREE.Bone | undefined {
    const candidates = BONE_SYNONYMS[name] ?? [name];
    for (const candidate of candidates) {
      const bone =
        this.bones.get(candidate) ?? this.boneAliases.get(normalizeBoneName(candidate));
      if (bone) return bone;
    }
    return undefined;
  }

  /**
   * Rotate a bone so its child points along a world-space direction. This is
   * far more predictable than guessing the local Euler axes of an imported rig.
   */
  private aimBone(name: string, childName: string, target: THREE.Vector3) {
    const bone = this.findBone(name);
    const child = this.findBone(childName);
    if (!bone || !child || !bone.parent || !this.model) return;

    this.model.updateMatrixWorld(true);
    const bonePos = new THREE.Vector3().setFromMatrixPosition(bone.matrixWorld);
    const childPos = new THREE.Vector3().setFromMatrixPosition(child.matrixWorld);
    const current = childPos.sub(bonePos);
    if (current.lengthSq() < 1e-8) return;
    current.normalize();

    const desired = target.clone().normalize();
    const worldDelta = new THREE.Quaternion().setFromUnitVectors(current, desired);

    const parentWorld = new THREE.Quaternion();
    bone.parent.getWorldQuaternion(parentWorld);
    const local = parentWorld
      .clone()
      .invert()
      .multiply(worldDelta)
      .multiply(parentWorld)
      .multiply(bone.quaternion);
    bone.quaternion.copy(local);
    bone.updateMatrixWorld(true);
  }

  private aimArms() {
    const toRad = Math.PI / 180;
    const arm = this.armAngle * toRad;
    const forearm = this.forearmAngle * toRad;

    for (const side of ['L', 'R'] as const) {
      const sign = side === 'L' ? 1 : -1;
      this.aimBone(
        `腕.${side}`,
        `腕捩.${side}`,
        new THREE.Vector3(sign * Math.sin(arm), -Math.cos(arm), 0.06),
      );
      this.model?.updateMatrixWorld(true);
      this.aimBone(
        `ひじ.${side}`,
        `手捩.${side}`,
        new THREE.Vector3(sign * 0.08, -Math.cos(forearm), Math.sin(forearm)),
      );
      this.model?.updateMatrixWorld(true);
    }
  }

  private applyBasePose() {
    for (const [name, bone] of this.bones) {
      const rest = this.restQuats.get(bone.uuid);
      if (!rest) continue;
      bone.quaternion.copy(rest);
      const offset = this.baseOffsets[name];
      if (offset) {
        bone.quaternion.multiply(
          new THREE.Quaternion().setFromEuler(new THREE.Euler(offset[0], offset[1], offset[2])),
        );
      }
    }
    this.model?.updateMatrixWorld(true);
    this.aimArms();
    this.model?.updateMatrixWorld(true);

    this.baseQuats.clear();
    for (const bone of this.bones.values()) {
      this.baseQuats.set(bone.name, bone.quaternion.clone());
    }

    const upper = this.findBone('腕.L');
    const elbow = this.findBone('腕捩.L');
    if (upper && elbow) {
      this.model?.updateMatrixWorld(true);
      const a = new THREE.Vector3().setFromMatrixPosition(upper.matrixWorld);
      const b = new THREE.Vector3().setFromMatrixPosition(elbow.matrixWorld);
      this.poseDebug.armDir = b.sub(a).normalize().toArray().map((v) => Number(v.toFixed(3)));
    }
  }

  private animateBone(name: string, x: number, y: number, z: number) {
    const bone = this.findBone(name);
    if (!bone) return;
    const base = this.baseQuats.get(bone.name) ?? this.restQuats.get(bone.uuid);
    if (!base) return;
    bone.quaternion
      .copy(base)
      .multiply(new THREE.Quaternion().setFromEuler(new THREE.Euler(x, y, z)));
  }

  setAnalyser(analyser: AnalyserNode | null) {
    this.analyser = analyser;
    this.waveData = analyser ? new Uint8Array(analyser.fftSize) : null;
    this.energy = 0;
  }

  setSpeaking(speaking: boolean) {
    this.speaking = speaking;
    if (!speaking) this.energy = 0;
  }

  setLook(x: number, y: number) {
    this.pointer.set(x, y);
  }

  private onPointerMove = (event: PointerEvent) => {
    this.pointer.set(
      (event.clientX / window.innerWidth) * 2 - 1,
      -((event.clientY / window.innerHeight) * 2 - 1),
    );
  };

  private setLayout() {
    const host = this.canvas.parentElement ?? this.canvas;
    const aspect = Math.max(1, host.clientWidth) / Math.max(1, host.clientHeight);
    const portrait = aspect < 0.85;

    if (this.model) {
      this.model.position.x = this.modelBaseX + (portrait ? 0 : 0.5);
    }

    if (portrait) {
      this.cameraBase.set(0, 1.22, 3.7);
      this.lookAtBase.set(0, 1.02, 0);
      this.camera.fov = 32;
    } else {
      this.cameraBase.set(0.02, 1.26, 2.8);
      this.lookAtBase.set(0.22, 1.06, 0);
      this.camera.fov = 30;
    }
    this.camera.updateProjectionMatrix();
  }

  private resize() {
    const host = this.canvas.parentElement ?? this.canvas;
    const width = Math.max(1, host.clientWidth);
    const height = Math.max(1, host.clientHeight);
    this.renderer.setSize(width, height, false);
    this.camera.aspect = width / height;
    this.setLayout();
  }

  private updateMouth(dt: number) {
    if (this.mouth) {
      let target = 0;
      if (this.speaking && this.analyser && this.waveData) {
        this.analyser.getByteTimeDomainData(this.waveData);
        let sum = 0;
        for (const value of this.waveData) {
          const x = (value - 128) / 128;
          sum += x * x;
        }
        const rms = Math.sqrt(sum / this.waveData.length);
        target = Math.min(1, rms * 4.2);
      }
      this.energy += (target - this.energy) * Math.min(1, dt * 18);
      if (this.expressionEnabled) this.setExpression('にっこり', 0.18 * (1 - this.energy));

      const influences = this.mouth.mesh.morphTargetInfluences;
      if (influences) {
        const index = this.mouth.index;
        const open = this.mouthOverride ?? Math.min(1, this.energy * 1.35);
        for (const key of ['あ', 'い', 'う', 'え', 'お']) {
          if (index[key] !== undefined) influences[index[key]] = 0;
        }
        if (index['あ'] !== undefined) influences[index['あ']] = open * 0.9;
        if (index['い'] !== undefined) influences[index['い']] = Math.max(0, open - 0.55) * 0.5;
        if (index['う'] !== undefined) influences[index['う']] = Math.max(0, 0.4 - open) * 0.2;
      }
    }
  }

  private updateBlink(dt: number) {
    if (!this.blink) return;
    this.blinkCooldown -= dt;
    if (this.blinkCooldown <= 0 && this.blinkRemaining <= 0) {
      this.blinkRemaining = this.blinkDuration;
      this.blinkCooldown = 2.6 + Math.random() * 3.4;
    }
    let value = 0;
    if (this.blinkRemaining > 0) {
      this.blinkRemaining = Math.max(0, this.blinkRemaining - dt);
      const progress = 1 - this.blinkRemaining / this.blinkDuration;
      value = Math.sin(progress * Math.PI);
    }
    const influences = this.blink.mesh.morphTargetInfluences;
    if (influences) influences[this.blink.index] = value;
  }

  private loop = () => {
    if (this.disposed) return;
    this.raf = requestAnimationFrame(this.loop);

    const dt = Math.min(0.05, this.clock.getDelta());
    const t = this.clock.elapsedTime;

    this.pointerSmooth.lerp(this.pointer, Math.min(1, dt * 3));

    if (this.model) {
      const breath = Math.sin(t * 1.55) * 0.011;
      const sway = Math.sin(t * 0.62) * 0.012;
      this.animateBone('上半身2', breath * 0.6, 0, sway);
      this.animateBone('首', 0.02 + this.pointerSmooth.y * 0.05, this.pointerSmooth.x * 0.08, -sway * 0.4);
      this.animateBone(
        '頭',
        -this.pointerSmooth.y * 0.04,
        this.pointerSmooth.x * 0.06,
        Math.sin(t * 0.5) * 0.008,
      );
      this.animateBone('腕.L', Math.sin(t * 1.1) * 0.008, 0, 0);
      this.animateBone('腕.R', Math.sin(t * 1.1 + 1.2) * 0.008, 0, 0);
    }

    this.updateBlink(dt);
    this.updateMouth(dt);

    this.camera.position.x = this.cameraBase.x + this.pointerSmooth.x * 0.03;
    this.camera.position.y = this.cameraBase.y + this.pointerSmooth.y * 0.02;
    this.camera.position.z = this.cameraBase.z;
    this.camera.lookAt(this.lookAtBase);

    this.renderer.render(this.scene, this.camera);
  };

  dispose() {
    this.disposed = true;
    cancelAnimationFrame(this.raf);
    this.resizeObserver?.disconnect();
    window.removeEventListener('pointermove', this.onPointerMove);
    this.mmd?.dispose();
    this.mmd = null;
    this.renderer.dispose();
  }
}

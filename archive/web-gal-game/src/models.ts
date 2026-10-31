import type { ModelType } from './three/CharacterStage';

export interface ModelDef {
  id: string;
  label: string;
  type: ModelType;
  url: string;
  resourcePath?: string;
  flip?: boolean;
  armAngle?: number;
  forearmAngle?: number;
  materialMode?: 'toon' | 'physical';
  note: string;
}

/**
 * Model registry. Add a file under public/models/ and an entry here; the
 * settings panel and the `?model=` query both use this list.
 */
export const MODELS: ModelDef[] = [
  {
    id: 'pmx',
    label: 'Vodyanitsa · PMX',
    type: 'pmx',
    url: '/models/vodyanitsa/Vodyanitsa.pmx',
    resourcePath: '/models/vodyanitsa/',
    armAngle: 22,
    forearmAngle: 25,
    materialMode: 'physical',
    note: '标准 PMX / MMD 骨骼与表情 · 推荐',
  },
  {
    id: 'glb',
    label: 'Vodyanitsa · GLB',
    type: 'glb',
    url: '/models/arcore.glb',
    note: '旧 GLB 备用 · 材质/骨骼有缺失',
  },
];

export const DEFAULT_MODEL_ID = 'pmx';

export function getModel(id: string): ModelDef {
  return MODELS.find((model) => model.id === id) ?? MODELS[0];
}

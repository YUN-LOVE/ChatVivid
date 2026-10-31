<template>
  <div class="relative h-full w-full">
    <canvas ref="canvas" class="block h-full w-full" />
    <slot />
  </div>
</template>

<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue';
import { CharacterStage, type ModelType, type StageDiagnostics } from '../three/CharacterStage';

const props = defineProps<{
  modelUrl: string;
  modelType: ModelType;
  resourcePath?: string;
  flip?: boolean;
  armAngle?: number;
  forearmAngle?: number;
  materialMode?: 'toon' | 'physical';
}>();

const emit = defineEmits<{
  ready: [StageDiagnostics];
  progress: [number];
  error: [string];
}>();

const canvas = ref<HTMLCanvasElement | null>(null);
let stage: CharacterStage | null = null;

onMounted(async () => {
  if (!canvas.value) return;
  stage = new CharacterStage(canvas.value);
  try {
    const diagnostics = await stage.load({
      url: props.modelUrl,
      type: props.modelType,
      resourcePath: props.resourcePath,
      flip: props.flip,
      armAngle: props.armAngle,
      forearmAngle: props.forearmAngle,
      materialMode: props.materialMode,
      onProgress: (ratio) => emit('progress', ratio),
    });
    emit('ready', diagnostics);
  } catch (error) {
    console.error(error);
    emit('error', error instanceof Error ? error.message : String(error));
  }
});

onBeforeUnmount(() => {
  stage?.dispose();
  stage = null;
});

defineExpose({
  get stage() {
    return stage;
  },
});
</script>

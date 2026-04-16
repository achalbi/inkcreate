const DEFAULT_CAPTURE_QUALITY_PRESET = "optimized";

const CAPTURE_QUALITY_PROFILES = {
  optimized: {
    maxDimension: 1800,
    jpegQuality: 0.8,
    previewQuality: 0.8,
    videoWidth: 2048,
    videoHeight: 1536
  },
  high: {
    maxDimension: 2500,
    jpegQuality: 0.9,
    previewQuality: 0.84,
    videoWidth: 2560,
    videoHeight: 1920
  },
  original: {
    maxDimension: null,
    jpegQuality: 0.98,
    previewQuality: 0.84,
    videoWidth: 2560,
    videoHeight: 1920
  }
};

export function currentCaptureQualityPreset() {
  const preset = document.documentElement?.dataset?.captureQualityPreset;
  return CAPTURE_QUALITY_PROFILES[preset] ? preset : DEFAULT_CAPTURE_QUALITY_PRESET;
}

export function currentCaptureQualityProfile() {
  return CAPTURE_QUALITY_PROFILES[currentCaptureQualityPreset()];
}

export function cameraVideoConstraints() {
  const profile = currentCaptureQualityProfile();

  return {
    facingMode: { ideal: "environment" },
    width: { ideal: profile.videoWidth },
    height: { ideal: profile.videoHeight }
  };
}

export async function optimizeImageFiles(files) {
  return Promise.all(Array.from(files || []).map((file) => optimizeImageFile(file)));
}

export async function optimizeImageFile(file) {
  const preset = currentCaptureQualityPreset();
  const profile = currentCaptureQualityProfile();

  if (!file?.type?.startsWith("image/") || preset === "original") {
    return file;
  }

  let source;

  try {
    source = await loadImageSource(file);
  } catch (_error) {
    return file;
  }

  try {
    const resizedCanvas = resizeSourceToCanvas(source, profile.maxDimension);
    const blob = await canvasToBlob(resizedCanvas, "image/jpeg", profile.jpegQuality);

    if (!blob) {
      return file;
    }

    if (blob.size >= file.size) {
      return file;
    }

    return new File([blob], replaceExtension(file.name, "jpg"), {
      type: "image/jpeg",
      lastModified: file.lastModified || Date.now()
    });
  } finally {
    source.close?.();
  }
}

export async function canvasToCaptureFile(canvas, { fileNamePrefix = "capture" } = {}) {
  const processedCanvas = renderCanvasForPreset(canvas);
  const blob = await canvasToBlob(processedCanvas, "image/jpeg", currentCaptureQualityProfile().jpegQuality);

  if (!blob) {
    return null;
  }

  return new File([blob], `${fileNamePrefix}-${Date.now()}.jpg`, { type: "image/jpeg" });
}

export function canvasToPreviewDataUrl(canvas) {
  return renderCanvasForPreset(canvas).toDataURL("image/jpeg", currentCaptureQualityProfile().previewQuality);
}

export function canvasToCaptureDataUrl(canvas) {
  return renderCanvasForPreset(canvas).toDataURL("image/jpeg", currentCaptureQualityProfile().jpegQuality);
}

function renderCanvasForPreset(canvas) {
  return resizeSourceToCanvas(canvas, currentCaptureQualityProfile().maxDimension);
}

function resizeSourceToCanvas(source, maxDimension) {
  const { width, height } = targetDimensions(source.width, source.height, maxDimension);

  if (width === source.width && height === source.height && source instanceof HTMLCanvasElement) {
    return source;
  }

  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;

  const context = canvas.getContext("2d", { alpha: false });
  context.drawImage(source, 0, 0, width, height);

  return canvas;
}

function targetDimensions(width, height, maxDimension) {
  if (!maxDimension) {
    return { width, height };
  }

  const longestSide = Math.max(width, height);
  if (longestSide <= maxDimension) {
    return { width, height };
  }

  const scale = maxDimension / longestSide;
  return {
    width: Math.max(1, Math.round(width * scale)),
    height: Math.max(1, Math.round(height * scale))
  };
}

async function loadImageSource(file) {
  if (typeof createImageBitmap === "function") {
    try {
      return await createImageBitmap(file);
    } catch (_error) {
      // Fall through to Image for browsers that expose createImageBitmap but cannot decode the file type.
    }
  }

  return new Promise((resolve, reject) => {
    const objectUrl = URL.createObjectURL(file);
    const image = new Image();
    image.onload = () => {
      URL.revokeObjectURL(objectUrl);
      resolve(image);
    };
    image.onerror = (error) => {
      URL.revokeObjectURL(objectUrl);
      reject(error);
    };
    image.src = objectUrl;
  });
}

function canvasToBlob(canvas, type, quality) {
  return new Promise((resolve) => canvas.toBlob(resolve, type, quality));
}

function replaceExtension(fileName, nextExtension) {
  const normalizedName = String(fileName || "capture").replace(/\.[^.]+$/, "");
  return `${normalizedName}.${nextExtension}`;
}

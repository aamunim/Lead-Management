// Picks an image file in the browser (0B.10 logo). The phone app gets a native picker with its next app build
// (adding one now would need a new install instead of an over-the-air update).
export const canPickImage = true;

export function pickImage(): Promise<{ file: Blob; extension: string } | null> {
  return new Promise((resolve) => {
    const input = globalThis.document.createElement('input');
    input.type = 'file';
    input.accept = 'image/png,image/jpeg,image/webp';
    input.onchange = () => {
      const file = input.files?.[0];
      if (!file) return resolve(null);
      const extension = file.type === 'image/jpeg' ? 'jpg' : file.type === 'image/webp' ? 'webp' : 'png';
      resolve({ file, extension });
    };
    input.click();
  });
}

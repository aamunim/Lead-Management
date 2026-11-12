// Picks an image file (0B.10 logo). On the phone this arrives with the next app build (a native picker needs a new
// install, not an over-the-air update); the web app can upload the logo meanwhile. See pick-image.web.ts.
export const canPickImage = false;

export function pickImage(): Promise<{ file: Blob; extension: string } | null> {
  return Promise.resolve(null);
}

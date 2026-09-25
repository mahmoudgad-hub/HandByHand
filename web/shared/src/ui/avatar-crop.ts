export function cropGeometry(width: number, height: number, zoom: number, x: number, y: number) {
  const side = Math.min(width, height) / Math.max(1, zoom);
  return { side, sx: (width-side)*Math.max(0,Math.min(100,x))/100, sy: (height-side)*Math.max(0,Math.min(100,y))/100 };
}

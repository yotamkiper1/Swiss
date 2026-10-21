import { Composition } from "remotion";
import { Commercial } from "./Commercial";
import { FPS, H, TOTAL, W } from "./timeline";

export const Root: React.FC = () => (
  <Composition id="Commercial" component={Commercial} durationInFrames={TOTAL} fps={FPS} width={W} height={H} />
);

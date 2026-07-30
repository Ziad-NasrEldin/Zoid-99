import { Suspense } from "react";

import { RadarPage as RadarView } from "@/components/radar-page";

export default function RadarPage() {
  return (
    <Suspense fallback={<div role="status">Loading Radar</div>}>
      <RadarView />
    </Suspense>
  );
}

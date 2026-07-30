import { Suspense } from "react";

import { TopicsPage as TopicsView } from "@/components/topics-page";

export default function TopicsPage() {
  return (
    <Suspense fallback={<div role="status">Loading Topics</div>}>
      <TopicsView />
    </Suspense>
  );
}

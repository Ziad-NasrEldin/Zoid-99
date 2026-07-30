import React from "react";

type EmptyStateProps = {
  eyebrow: string;
  title: string;
  body: string;
};

export function EmptyState({ eyebrow, title, body }: EmptyStateProps) {
  return (
    <div className="empty-state" role="status" aria-live="polite">
      <p className="empty-eyebrow">{eyebrow}</p>
      <h2>{title}</h2>
      <p>{body}</p>
    </div>
  );
}

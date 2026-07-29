import { OperatorLogin } from "@/components/operator-login";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string | string[] }>;
}) {
  const requested = (await searchParams).next;
  const candidate = typeof requested === "string" ? requested : "/today";
  const nextPath = candidate.startsWith("/") && !candidate.startsWith("//") && !candidate.startsWith("/login")
    ? candidate
    : "/today";
  return <OperatorLogin nextPath={nextPath} />;
}

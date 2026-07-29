import { expect, test, type Page } from "@playwright/test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const bootstrap = JSON.parse(readFileSync(resolve(process.cwd(), "../packages/contracts/fixtures/bootstrap.json"), "utf8")) as {
  opportunities: Array<Record<string, unknown>>;
};
const opportunity = bootstrap.opportunities[0]!;
const opportunityID = String(opportunity.id);

async function stubResearchGateway(page: Page) {
  let disposition = "active";
  await page.route("**/api/gateway/**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    if (url.pathname.endsWith("/bootstrap")) {
      return route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ ...bootstrap, sourceHealth: [{ group: "US & Official", state: "Connected", lastActivity: "2026-07-28T08:05:00.000Z", evidence: "1 official item collected with a source link and timestamp.", repairAction: "Review", dataTruth: "Live" }] }) });
    }
    if (url.pathname.endsWith(`/opportunities/${opportunityID}/disposition`)) {
      const payload = request.postDataJSON() as { disposition: string; changedAt: string; mutationID: string };
      disposition = payload.disposition;
      return route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ opportunityID, disposition, changedAt: payload.changedAt, mutationID: payload.mutationID, outcome: "applied" }) });
    }
    if (url.pathname.endsWith(`/opportunities/${opportunityID}`)) {
      return route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ ...opportunity, disposition }) });
    }
    return route.continue();
  });
}

test("Today opens a real evidence-preserving detail and persists a disposition through the gateway", async ({ page }) => {
  await stubResearchGateway(page);
  await page.goto("/today");

  await expect(page.getByRole("heading", { name: "Today" })).toBeVisible();
  await expect(page.getByText("Live data")).toBeVisible();
  await expect(page.getByRole("link", { name: "Official release 99" })).toBeVisible();
  await page.getByRole("button", { name: "Watch" }).click();
  await expect(page.getByRole("button", { name: "Watch" })).toHaveAttribute("aria-pressed", "true");

  await page.getByRole("link", { name: "Official release 99" }).click();
  await expect(page).toHaveURL(new RegExp(`/opportunities/${opportunityID}$`));
  await expect(page.getByRole("heading", { name: "Score breakdown" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Regional reading" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Arabic coverage" })).toBeVisible();
  await expect(page.getByText("Open original source")).toHaveAttribute("href", "https://official.example/releases/99");
  await expect(page.getByRole("heading", { name: "Supporting source items" })).toBeVisible();
  await page.reload();
  await expect(page.getByRole("button", { name: "Watch" })).toHaveAttribute("aria-pressed", "true");
  await page.screenshot({ path: "../.scratch/zoid-web/proof/wp-06-today-detail-desktop.png", fullPage: true });
});

test.describe("mobile opportunity detail", () => {
  test.use({ viewport: { width: 390, height: 844 }, isMobile: true });

  test("renders full-screen detail and returns with the explicit back control", async ({ page }) => {
    await stubResearchGateway(page);
    await page.goto(`/opportunities/${opportunityID}`);

    await expect(page.getByRole("heading", { name: "Score breakdown" })).toBeVisible();
    await expect(page.getByRole("link", { name: /Back to Today/ })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Supporting source items" })).toBeVisible();
    await page.screenshot({ path: "../.scratch/zoid-web/proof/wp-06-opportunity-mobile.png", fullPage: true });

    await page.getByRole("link", { name: /Back to Today/ }).click();
    await expect(page).toHaveURL(/\/today$/);
    await expect(page.getByRole("heading", { name: "Today" })).toBeVisible();
  });
});

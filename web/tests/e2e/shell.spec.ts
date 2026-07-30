import { expect, test, type Page } from "@playwright/test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const bootstrapFixture = readFileSync(
  resolve(process.cwd(), "../packages/contracts/fixtures/bootstrap.json"),
  "utf8",
);

async function stubBootstrap(page: Page) {
  await page.route("**/api/gateway/bootstrap", (route) => route.fulfill({
    status: 200,
    contentType: "application/json",
    body: bootstrapFixture,
  }));
}

test("desktop shell exposes every product destination without data", async ({ page }) => {
  await stubBootstrap(page);
  await page.goto("/today");

  await expect(page).toHaveTitle(/Zoid 99/);
  await expect(page.getByRole("main")).toContainText("Official release 99");
  await expect(page.locator(".shell-status")).toContainText("API v1");
  await expect(page.getByRole("link", { name: "Today" }).first()).toHaveAttribute("aria-current", "page");
  await expect(page.getByText("Gateway-backed research data appears here when available.", { exact: true })).toBeVisible();

  const destinations = ["Today", "Radar", "Watchlists", "Notifications", "Topics", "Comments", "Sources", "Settings"];
  for (const destination of destinations) {
    await expect(page.getByRole("link", { name: destination }).first()).toBeVisible();
  }
});

test("Radar URL filters and Topics search restore through browser Back with development identity", async ({ page }) => {
  await page.setExtraHTTPHeaders({ "x-zoid-dev-identity": "developer@local.invalid" });
  await page.goto("/radar?source=YouTube&verification=Confirmed");
  await expect(page.getByRole("heading", { name: "Live Radar" })).toBeVisible();
  await expect(page.getByRole("combobox", { name: "Source" })).toHaveValue("YouTube");
  await expect(page.getByRole("combobox", { name: "Verification" })).toHaveValue("Confirmed");

  await page.getByRole("textbox", { name: "Search research" }).fill("agents");
  await page.getByRole("button", { name: "Apply filters" }).click();
  await expect(page).toHaveURL(/source=YouTube.*verification=Confirmed.*search=agents|search=agents.*source=YouTube/);

  await page.goBack();
  await expect(page.getByRole("textbox", { name: "Search research" })).toHaveValue("");
  await expect(page.getByRole("combobox", { name: "Source" })).toHaveValue("YouTube");

  await page.goto("/topics?search=agents");
  await expect(page.getByRole("heading", { name: "Topics" })).toBeVisible();
  await expect(page.getByRole("textbox", { name: "Search topics" })).toHaveValue("agents");
});

test.describe("mobile shell", () => {
  test.use({ viewport: { width: 390, height: 844 }, isMobile: true });

  test("provides touch navigation and a keyboard-reachable More menu", async ({ page }) => {
    await stubBootstrap(page);
    await page.goto("/today");

    await expect(page.locator(".mobile-bottom-nav")).toBeVisible();
    await expect(page.locator(".desktop-rail")).toBeHidden();

    const moreButton = page.getByRole("button", { name: "Open more destinations" });
    await expect(moreButton).toBeVisible();
    await moreButton.focus();
    await expect(moreButton).toBeFocused();

    const moreBounds = await moreButton.evaluate((element) => {
      const rect = element.getBoundingClientRect();
      const styles = getComputedStyle(element);
      return { width: rect.width, height: rect.height, minWidth: styles.minWidth, minHeight: styles.minHeight };
    });
    expect(moreBounds.width).toBeGreaterThanOrEqual(44);
    expect(moreBounds.height).toBeGreaterThanOrEqual(44);
    expect(moreBounds.minWidth).toBe("44px");
    expect(moreBounds.minHeight).toBe("44px");

    await moreButton.click();
    const moreNavigation = page.getByRole("navigation", { name: "More destinations" });
    await expect(moreNavigation).toBeVisible();
    await expect(moreNavigation.getByRole("link", { name: "Settings" })).toBeVisible();

    const closeButton = moreNavigation.getByRole("button", { name: "Close more destinations" });
    expect(await closeButton.count()).toBe(1);
    const closeBounds = await closeButton.evaluate((element) => {
      const rect = element.getBoundingClientRect();
      const styles = getComputedStyle(element);
      return { width: rect.width, height: rect.height, minWidth: styles.minWidth, minHeight: styles.minHeight };
    });
    expect(closeBounds.width).toBeGreaterThanOrEqual(44);
    expect(closeBounds.height).toBeGreaterThanOrEqual(44);
    expect(closeBounds.minWidth).toBe("44px");
    expect(closeBounds.minHeight).toBe("44px");
  });
});

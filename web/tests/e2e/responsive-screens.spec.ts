import { expect, test, type Page } from "@playwright/test";

const workspaceRoutes = [
  "/today",
  "/radar",
  "/topics",
  "/comments",
  "/watchlists",
  "/notifications",
  "/sources",
  "/settings",
];

const viewports = [
  { name: "phone", width: 390, height: 844 },
  { name: "tablet portrait", width: 768, height: 1024 },
  { name: "tablet landscape", width: 1023, height: 900 },
  { name: "desktop", width: 1440, height: 900 },
];

async function expectNoHorizontalOverflow(page: Page) {
  const dimensions = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth,
  }));

  expect(dimensions.scrollWidth).toBeLessThanOrEqual(dimensions.clientWidth);
}

for (const viewport of viewports) {
  test.describe(`${viewport.name} responsive screens`, () => {
    test.use({ viewport: { width: viewport.width, height: viewport.height } });

    test("keeps every workspace screen within the viewport", async ({ page }) => {
      for (const route of workspaceRoutes) {
        await page.goto(route);
        await expect(page.locator("#main-content")).toBeVisible();
        await expectNoHorizontalOverflow(page);
      }
    });

    test("uses the appropriate navigation density", async ({ page }) => {
      await page.goto("/today");

      if (viewport.width <= 1023) {
        await expect(page.locator(".mobile-topbar")).toBeVisible();
        await expect(page.locator(".mobile-bottom-nav")).toBeVisible();
        await expect(page.locator(".desktop-rail")).toBeHidden();
      } else {
        await expect(page.locator(".desktop-rail")).toBeVisible();
        await expect(page.locator(".mobile-topbar")).toBeHidden();
        await expect(page.locator(".mobile-bottom-nav")).toBeHidden();
      }
    });
  });
}

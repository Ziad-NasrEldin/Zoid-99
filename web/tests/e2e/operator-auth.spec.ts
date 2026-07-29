import { expect, test } from "@playwright/test";

const operatorPassword = process.env.ZOID99_E2E_OPERATOR_PASSWORD;

test("operator password protects the workspace and logout revokes the session", async ({ page }) => {
  test.skip(!operatorPassword, "ZOID99_E2E_OPERATOR_PASSWORD is required for the operator auth E2E");

  await page.goto("/today");
  await expect(page).toHaveURL(/\/login\?next=%2Ftoday$/);
  await expect(page.getByRole("heading", { name: "Enter Zoid 99" })).toBeVisible();

  await page.getByLabel("Operator password").fill("incorrect-operator-password");
  await page.getByRole("button", { name: "Enter workspace" }).click();
  await expect(page.locator(".operator-login-error")).toHaveText("Invalid operator password");

  await page.getByLabel("Operator password").fill(operatorPassword!);
  await page.getByRole("button", { name: "Enter workspace" }).click();
  await expect(page).toHaveURL(/\/today$/);
  await expect(page.getByRole("heading", { name: "Today" })).toBeVisible();

  await page.reload();
  await expect(page.getByRole("heading", { name: "Today" })).toBeVisible();

  await page.getByRole("button", { name: "Sign out" }).click();
  await expect(page).toHaveURL(/\/login$/);

  await page.goto("/today");
  await expect(page).toHaveURL(/\/login\?next=%2Ftoday$/);
});

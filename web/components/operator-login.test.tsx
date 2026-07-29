import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { OperatorLogin } from "@/components/operator-login";

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe("OperatorLogin", () => {
  it("submits the operator password and presents a safe invalid-password error", async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify({
      message: "Invalid operator password",
    }), { status: 401, headers: { "content-type": "application/json" } }));
    vi.stubGlobal("fetch", fetchMock);
    render(<OperatorLogin />);

    fireEvent.change(screen.getByLabelText("Operator password"), { target: { value: "wrong-password" } });
    fireEvent.click(screen.getByRole("button", { name: "Enter workspace" }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalledWith("/api/auth/login", expect.objectContaining({
      method: "POST",
      body: JSON.stringify({ password: "wrong-password" }),
    })));
    expect(await screen.findByRole("alert")).toHaveTextContent("Invalid operator password");
  });

  it("supports revealing and hiding the password", () => {
    render(<OperatorLogin />);
    const input = screen.getByLabelText("Operator password");
    expect(input).toHaveAttribute("type", "password");
    fireEvent.click(screen.getByRole("button", { name: "Show password" }));
    expect(input).toHaveAttribute("type", "text");
    fireEvent.click(screen.getByRole("button", { name: "Hide password" }));
    expect(input).toHaveAttribute("type", "password");
  });
});

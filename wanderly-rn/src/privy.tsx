import { PrivyProvider, usePrivy } from "@privy-io/react-auth";
import { ReactNode } from "react";

const privyAppId = "__WANDERLY_PRIVY_APP_ID__";
const privyClientId = "__WANDERLY_PRIVY_APP_CLIENT_ID__";

function hasConfiguredValue(value: string): boolean {
  return value.length > 0 && !value.startsWith("__WANDERLY_");
}

export function WanderlyPrivyProvider({ children }: { children: ReactNode }) {
  if (!hasPrivyConfig()) {
    return <>{children}</>;
  }

  return (
    <PrivyProvider
      appId={privyAppId}
      clientId={privyClientId}
      config={{
        appearance: {
          theme: "light",
          accentColor: "#CB623D",
          logo: undefined,
        },
        loginMethods: ["email", "google", "apple"],
      }}
    >
      {children}
    </PrivyProvider>
  );
}

export function useOptionalPrivy() {
  try {
    return usePrivy();
  } catch {
    return null;
  }
}

export function hasPrivyConfig(): boolean {
  return hasConfiguredValue(privyAppId) && hasConfiguredValue(privyClientId);
}

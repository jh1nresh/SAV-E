import { PrivyProvider, usePrivy } from "@privy-io/react-auth";
import { ReactNode } from "react";

const privyAppId = process.env.EXPO_PUBLIC_PRIVY_APP_ID;
const privyClientId = process.env.EXPO_PUBLIC_PRIVY_APP_CLIENT_ID;

export function WanderlyPrivyProvider({ children }: { children: ReactNode }) {
  if (!privyAppId || !privyClientId) {
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
  return Boolean(privyAppId && privyClientId);
}

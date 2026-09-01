import type { CapacitorConfig } from "@capacitor/cli";

const config: CapacitorConfig = {
  appId: "com.dictaste.mobile",
  appName: "Dictaste",
  webDir: "dist",
  backgroundColor: "#090a0b",
  ios: {
    contentInset: "automatic",
    preferredContentMode: "mobile"
  },
  android: {
    backgroundColor: "#090a0b",
    allowMixedContent: false
  }
};

export default config;


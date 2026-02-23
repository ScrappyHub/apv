export const metadata = {
  title: "APV",
  description: "AI Provenance Verifier â€” UI"
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body style={{ fontFamily: "ui-sans-serif, system-ui", margin: 0, padding: 0 }}>
        <div style={{ padding: 16, borderBottom: "1px solid #333" }}>
          <b>APV</b> <span style={{ opacity: 0.7 }}>Tier-1 UI scaffold</span>
        </div>
        <div style={{ padding: 16 }}>
          {children}
        </div>
      </body>
    </html>
  );
}

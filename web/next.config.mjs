/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  webpack: (config, { webpack }) => {
    // RainbowKit's Coinbase/Base connector pulls in @coinbase/cdp-sdk, which
    // lazily references optional @x402/* payment packages we don't install.
    // Ignore them so the client bundle builds; these code paths are never hit.
    config.plugins.push(
      new webpack.IgnorePlugin({ resourceRegExp: /^@x402\// }),
      // MetaMask SDK optionally imports React Native async-storage in the browser build.
      new webpack.IgnorePlugin({
        resourceRegExp: /^@react-native-async-storage\/async-storage$/,
      }),
    );
    config.externals.push("pino-pretty", "lokijs", "encoding");
    return config;
  },
};

export default nextConfig;

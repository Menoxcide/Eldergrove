This is a [Next.js](https://nextjs.org) project bootstrapped with [`create-next-app`](https://nextjs.org/docs/app/api-reference/cli/create-next-app).

## Getting Started

First, run the development server:

```bash
npm run dev
# or
yarn dev
# or
pnpm dev
# or
bun dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

You can start editing the page by modifying `app/page.tsx`. The page auto-updates as you edit the file.

This project uses [`next/font`](https://nextjs.org/docs/app/building-your-application/optimizing/fonts) to automatically optimize and load [Geist](https://vercel.com/font), a new font family for Vercel.

## Learn More

To learn more about Next.js, take a look at the following resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.

You can check out [the Next.js GitHub repository](https://github.com/vercel/next.js) - your feedback and contributions are welcome!

## Deploy on Vercel

The easiest way to deploy your Next.js app is to use the [Vercel Platform](https://vercel.com/new?utm_medium=default-template&filter=next.js&utm_source=create-next-app&utm_campaign=create-next-app-readme) from the creators of Next.js.

Check out our [Next.js deployment documentation](https://nextjs.org/docs/app/building-your-application/deploying) for more details.

## Authentication

This application supports both email/password authentication and Google OAuth authentication.

### Google OAuth Setup

To enable Google OAuth authentication, follow the instructions in [GOOGLE_OAUTH_SETUP.md](GOOGLE_OAUTH_SETUP.md).

## Ad Configuration

This application supports rewarded video ads for both mobile (via AdMob) and web (via Google Ad Manager).

### Mobile Ads (AdMob)

For mobile platforms (iOS/Android), configure the following environment variables:

```bash
NEXT_PUBLIC_ADMOB_APP_ID_IOS=your-ios-app-id
NEXT_PUBLIC_ADMOB_APP_ID_ANDROID=your-android-app-id
NEXT_PUBLIC_ADMOB_REWARDED_AD_UNIT_ID_IOS=your-ios-ad-unit-id
NEXT_PUBLIC_ADMOB_REWARDED_AD_UNIT_ID_ANDROID=your-android-ad-unit-id
```

### Web Ads (Google Ad Manager)

To enable real video ads on web instead of mock ads, configure Google Ad Manager:

1. Set up a Google Ad Manager account and create a rewarded video ad unit
2. Configure the following environment variables:

```bash
NEXT_PUBLIC_GAM_PUBLISHER_ID=your-publisher-id
NEXT_PUBLIC_GAM_REWARDED_AD_UNIT_ID=your-ad-unit-id
```

**Note:** If Google Ad Manager is not configured, the application will fall back to a 30-second mock ad timer on web platforms. This is useful for development and testing.

### Ad Behavior

- **Mobile**: Uses AdMob SDK via Capacitor to display real rewarded video ads
- **Web (with GAM)**: Uses Google Ad Manager IMA SDK to display real rewarded video ads
- **Web (without GAM)**: Displays a 30-second mock ad timer overlay
</content>

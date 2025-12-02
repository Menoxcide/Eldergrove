# Google OAuth Setup for Eldergrove

This document explains how to set up Google OAuth authentication for the Eldergrove application.

## Prerequisites

1. A Google Cloud Platform account
2. A project created in the Google Cloud Console
3. The Google+ API enabled for your project

## Setup Steps

### 1. Create OAuth Credentials in Google Cloud Console

1. Go to the [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project or create a new one
3. Navigate to "APIs & Services" > "Credentials"
4. Click "Create Credentials" > "OAuth client ID"
5. Select "Web application" as the application type
6. Set the following URLs:
   - **Authorized JavaScript origins**: `http://localhost:3000` (for development)
   - **Authorized redirect URIs**: `https://qregfrbtupgfdrequarz.supabase.co/auth/v1/callback` (Supabase OAuth callback URL)
7. For production, update with your production Supabase project URL:
   - **Authorized JavaScript origins**: `https://yourdomain.com`
   - **Authorized redirect URIs**: `https://your-production-supabase-project.supabase.co/auth/v1/callback`
8. Click "Create" and note down your Client ID and Client Secret

### 2. Configure Supabase Authentication

1. Go to your Supabase project dashboard
2. Navigate to "Authentication" > "Providers"
3. Find "Google" in the list of providers
4. Enable the Google provider
5. Enter your Google Client ID and Client Secret
6. Save the configuration

### 3. Update Environment Variables

Update your `.env.local` file with your actual Google OAuth credentials:

```env
NEXT_PUBLIC_GOOGLE_CLIENT_ID=your_actual_google_client_id_here
GOOGLE_CLIENT_SECRET=your_actual_google_client_secret_here
```

### 4. Testing the Implementation

1. Start your development server: `npm run dev`
2. Navigate to the login or register page
3. Click the "Sign in with Google" button
4. You should be redirected to Google's OAuth consent screen
5. After authenticating, you should be redirected back to your application

## Troubleshooting

### Common Issues

1. **Redirect URI mismatch**: Make sure the redirect URIs in your Google Cloud Console are set to your Supabase OAuth callback URL (e.g., `https://your-project.supabase.co/auth/v1/callback`). The OAuth implementation redirects to the Supabase callback URL for proper handling.

2. **Invalid client ID**: Verify that you've copied the correct Client ID from Google Cloud Console to your Supabase authentication settings.

3. **CORS errors**: Ensure that your authorized JavaScript origins match your application's domain.

### Debugging Tips

1. Check the browser console for any JavaScript errors
2. Verify network requests to see if the OAuth flow is being initiated correctly
3. Check Supabase logs for any authentication-related errors

## Security Considerations

1. Never commit actual credentials to version control
2. Use environment variables for sensitive information
3. Rotate your credentials periodically
4. Restrict your OAuth credentials to only the necessary domains
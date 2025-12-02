import { NextResponse, type NextRequest } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!

export async function middleware(request: NextRequest) {
  const requestUrl = new URL(request.url)
  const publicPaths = ['/', '/login', '/register', '/auth/callback']

  if (publicPaths.includes(requestUrl.pathname)) {
    return NextResponse.next()
  }

  // Create a Supabase client without cookie handling in middleware
  const supabase = createClient(supabaseUrl, supabaseKey)

  // Get session from cookies manually
  const token = request.cookies.get('sb-access-token')?.value
  const refreshToken = request.cookies.get('sb-refresh-token')?.value

  if (!token || !refreshToken) {
    return NextResponse.redirect(new URL('/login', request.url))
  }

  // Set the auth session
  const { data, error } = await supabase.auth.setSession({
    access_token: token,
    refresh_token: refreshToken,
  })

  if (error) {
    return NextResponse.redirect(new URL('/login', request.url))
  }

  if (!data.session) {
    return NextResponse.redirect(new URL('/login', request.url))
  }

  return NextResponse.next()
}

export const config = {
  matcher: [
    /*
     * Match all request paths except for the ones starting with:
     * - api (API routes)
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     */
    '/((?!api|_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
}
import { NextResponse, type NextRequest } from 'next/server'
import { createServerClient } from '@supabase/ssr'

export async function middleware(request: NextRequest) {
  const requestUrl = new URL(request.url)
  const publicPaths = ['/', '/login', '/register', '/auth/callback']

  console.log('Middleware running for:', requestUrl.pathname)

  if (publicPaths.includes(requestUrl.pathname)) {
    console.log('Public path, allowing access')
    return NextResponse.next()
  }

  console.log('Protected path, checking authentication')

  // Check environment variables
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
  const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY

  console.log('Environment check:', {
    hasUrl: !!supabaseUrl,
    hasKey: !!supabaseKey,
    url: supabaseUrl ? 'present' : 'missing',
    key: supabaseKey ? 'present' : 'missing'
  })

  if (!supabaseUrl || !supabaseKey) {
    console.error('Missing Supabase environment variables in middleware')
    return NextResponse.redirect(new URL('/login', request.url))
  }

  // Log cookies for debugging
  const allCookies = request.cookies.getAll()
  console.log('Cookies received:', allCookies.map(c => ({ name: c.name, hasValue: !!c.value })))

  // Create a Supabase server client with proper cookie handling
  const supabase = createServerClient(
    supabaseUrl,
    supabaseKey,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value, options }) => {
            request.cookies.set(name, value)
          })
        },
      },
    }
  )

  // Get the current session
  const { data: { session }, error } = await supabase.auth.getSession()

  console.log('Session check result:', { session: !!session, error: error?.message })

  if (error || !session) {
    console.log('No valid session, redirecting to login')
    return NextResponse.redirect(new URL('/login', request.url))
  }

  console.log('Valid session found, allowing access')
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
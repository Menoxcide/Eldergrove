'use client'

import LoginForm from '@/components/auth/LoginForm'

export const dynamic = 'force-dynamic'

export default function LoginPage() {
  return (
    <main className="min-h-screen bg-gradient-to-br from-slate-900 via-purple-900/50 to-slate-900 flex items-center justify-center p-8 md:p-24 relative overflow-hidden">
      <LoginForm />
    </main>
  )
}
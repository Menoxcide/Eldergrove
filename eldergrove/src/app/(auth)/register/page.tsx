'use client';

'use client'

import RegisterForm from '@/components/auth/RegisterForm'

export const dynamic = 'force-dynamic'

export default function RegisterPage() {
  return (
    <main className="min-h-screen bg-gradient-to-br from-slate-900 via-purple-900/50 to-slate-900 flex items-center justify-center p-8 md:p-24 relative overflow-hidden">
      <RegisterForm />
    </main>
  )
}
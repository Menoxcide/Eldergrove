export default function Loading() {
  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-purple-900/50 to-slate-900 flex items-center justify-center p-8 md:p-24 relative overflow-hidden">
      <div className="w-full max-w-md p-8 space-y-6 bg-white/10 backdrop-blur-md rounded-3xl shadow-2xl border border-white/20 mx-auto">
        <div className="text-center">
          <h2 className="text-3xl font-bold text-white mb-2">Loading...</h2>
          <p className="text-slate-300 text-sm">Please wait while we load the registration form</p>
          <div className="mt-6 flex justify-center">
            <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-emerald-500"></div>
          </div>
        </div>
      </div>
    </div>
  );
}
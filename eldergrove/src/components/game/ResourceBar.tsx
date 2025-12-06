'use client'

import { usePlayerStore } from '@/stores/usePlayerStore'
import { Skeleton } from '@/components/ui/LoadingSkeleton'
import Tooltip from '@/components/ui/Tooltip'
import ProgressBar from '@/components/ui/ProgressBar'
import { getCrystalsTooltip, getLevelTooltip, getXPTooltip } from '@/lib/tooltipUtils'

const ResourceBar = () => {
  const { crystals, level, xp, loading } = usePlayerStore()
  
  // Calculate XP progress: (current_xp % (level * 1000)) / (level * 1000) * 100
  const xpForNextLevel = level * 1000
  const xpProgress = xpForNextLevel > 0 ? ((xp % xpForNextLevel) / xpForNextLevel) * 100 : 0

  if (loading) {
    return (
      <div className="fixed md:relative top-0 left-0 right-0 z-50 flex items-center justify-center gap-8 p-6 bg-gradient-to-r from-slate-900 via-purple-900 to-slate-900 rounded-none md:rounded-2xl shadow-2xl border-b border-slate-700/50 md:border md:border-slate-700/50 backdrop-blur-md h-20">
        <Skeleton className="flex-1 h-12" />
        <Skeleton className="w-24 h-12" />
        <Skeleton className="flex-1 h-12" />
      </div>
    )
  }

  return (
    <div className="fixed md:relative top-0 left-0 right-0 z-50 flex items-center justify-between gap-4 p-4 md:p-6 bg-gradient-to-r from-indigo-900 via-purple-900 to-slate-900 rounded-none md:rounded-2xl shadow-2xl border-b border-indigo-500/30 md:border md:border-indigo-500/30 backdrop-blur-md text-white font-semibold text-base md:text-lg tracking-wide">
      <Tooltip content={getCrystalsTooltip(crystals, level)} position="bottom">
        <div className="flex items-center space-x-2 px-4 py-2 bg-slate-800/30 hover:bg-slate-700/50 rounded-xl transition-all duration-200 cursor-default">
          <span className="text-2xl md:text-3xl">💎</span>
          <span className="font-mono">{crystals.toLocaleString()}</span>
        </div>
      </Tooltip>
      <Tooltip content={getLevelTooltip(level, xp)} position="bottom">
        <div className="flex items-center space-x-2 px-4 py-2 bg-emerald-800/30 hover:bg-emerald-700/50 rounded-xl transition-all duration-200 cursor-default">
          <span className="text-xl md:text-2xl">👑</span>
          <span>Lvl {level}</span>
        </div>
      </Tooltip>
      <Tooltip content={getXPTooltip(xp, level)} position="bottom">
        <div className="flex flex-col items-end space-y-1 px-4 py-2 bg-amber-800/30 hover:bg-amber-700/50 rounded-xl transition-all duration-200 flex-1 min-w-[120px]">
          <div className="flex items-center justify-end space-x-2 w-full">
            <span className="text-lg">⭐</span>
            <span className="font-mono text-sm">{xp.toLocaleString()} XP</span>
          </div>
          <div className="w-full">
            <ProgressBar 
              progress={xpProgress} 
              className="h-1.5"
            />
          </div>
        </div>
      </Tooltip>
    </div>
  )
}

export default ResourceBar
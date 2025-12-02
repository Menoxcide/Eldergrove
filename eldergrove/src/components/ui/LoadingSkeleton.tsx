'use client'

import React, { HTMLAttributes } from 'react'

interface SkeletonProps extends HTMLAttributes<HTMLDivElement> {}

export function Skeleton({ className, ...props }: SkeletonProps) {
  return (
    <div
      className={`animate-pulse bg-slate-800/50 rounded-xl ${className ?? ''}`}
      {...props}
    />
  )
}
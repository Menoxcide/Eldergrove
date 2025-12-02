'use client';

import React, { useState, useEffect } from 'react';
import { useRouter, usePathname } from 'next/navigation';

const BottomNav: React.FC = () => {
  const router = useRouter();
  const pathname = usePathname();
  const [activeTab, setActiveTab] = useState<'town' | 'farm' | 'factory' | 'mine' | 'zoo' | 'coven' | 'profile'>('town');

  const tabs = [
    { id: 'town' as const, icon: '🏠', label: 'Town', path: '/game' },
    { id: 'farm' as const, icon: '🌱', label: 'Farm', path: '/game/farm' },
    { id: 'factory' as const, icon: '⚙️', label: 'Factory', path: '/game/factory' },
    { id: 'mine' as const, icon: '⛏️', label: 'Mine', path: '/game/mine' },
    { id: 'zoo' as const, icon: '🐾', label: 'Zoo', path: '/game/zoo' },
    { id: 'coven' as const, icon: '👥', label: 'Coven', path: '/game/coven' },
    { id: 'profile' as const, icon: '👤', label: 'Profile', path: '/game/profile' },
  ];

  // Update active tab based on current pathname
  useEffect(() => {
    const currentTab = tabs.find(tab => tab.path === pathname);
    if (currentTab) {
      setActiveTab(currentTab.id);
    } else if (pathname === '/game') {
      setActiveTab('town');
    }
  }, [pathname]);

  return (
    <nav className="fixed bottom-0 left-0 right-0 z-50 bg-gradient-to-t from-gray-900 to-gray-800 border-t border-gray-600 p-4 flex justify-around items-end h-20 shadow-2xl">
      {tabs.map((tab) => (
        <button
          key={tab.id}
          onClick={() => router.push(tab.path)}
          className={`flex flex-col items-center gap-1 p-2 rounded-xl transition-all duration-300 flex-1 mx-1 ${
            activeTab === tab.id
              ? 'text-emerald-400 bg-emerald-500/20 backdrop-blur-sm shadow-lg shadow-emerald-500/25 scale-110'
              : 'text-gray-400 hover:text-gray-200 hover:bg-gray-700/50 hover:scale-105'
          }`}
        >
          <span className="text-2xl">{tab.icon}</span>
          <span className="text-xs font-semibold tracking-wide">{tab.label}</span>
        </button>
      ))}
    </nav>
  );
};

export default BottomNav;
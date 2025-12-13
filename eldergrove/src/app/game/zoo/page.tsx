'use client';

import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { useZooStore, type ZooEnclosure, type AnimalType } from '@/stores/useZooStore';
import { usePlayerStore } from '@/stores/usePlayerStore';
import { useAdSpeedUp } from '@/hooks/useAdSpeedUp';
import { Skeleton } from '@/components/ui/LoadingSkeleton';
import { getItemIcon, getItemName } from '@/lib/itemUtils';
import { useErrorHandler } from '@/hooks/useErrorHandler';
import Tooltip, { type TooltipSection } from '@/components/ui/Tooltip';
import ProgressBar from '@/components/ui/ProgressBar';

interface EnclosureCardProps {
  enclosure: ZooEnclosure;
  animalTypes: AnimalType[];
  onAddAnimal: (enclosureId: number, animalTypeId: number, slot: number) => void;
  onRemoveAnimal: (enclosureId: number, slot: number) => void;
  onCollectProduction: (enclosureId: number, slot: number) => void;
  onStartBreeding: (enclosureId: number) => void;
  onCollectBred: (enclosureId: number) => void;
  onDeleteEnclosure: (enclosureId: number) => void;
  onCancelBreeding: (enclosureId: number) => void;
  onCancelProduction: (enclosureId: number, slot: number) => void;
}

const EnclosureCard: React.FC<EnclosureCardProps> = React.memo(({
  enclosure,
  animalTypes,
  onAddAnimal,
  onRemoveAnimal,
  onCollectProduction,
  onStartBreeding,
  onCollectBred,
  onDeleteEnclosure,
  onCancelBreeding,
  onCancelProduction
}) => {
  const [showAnimalModal, setShowAnimalModal] = useState<number | null>(null);
  const [currentTime, setCurrentTime] = useState(Date.now());
  const { watchAdForSpeedUp, canWatchAd, adsRemaining, loading: adLoading } = useAdSpeedUp();
  const animal1 = enclosure.animal1_id ? animalTypes.find(a => a.id === enclosure.animal1_id) : null;
  const animal2 = enclosure.animal2_id ? animalTypes.find(a => a.id === enclosure.animal2_id) : null;
  
  useEffect(() => {
    const interval = setInterval(() => {
      setCurrentTime(Date.now());
    }, 1000);
    return () => clearInterval(interval);
  }, []);

  const canCollect1 = animal1 && enclosure.animal1_produced_at && 
    new Date(enclosure.animal1_produced_at).getTime() + (animal1.produces_interval_minutes * 60 * 1000) <= currentTime;
  const canCollect2 = animal2 && enclosure.animal2_produced_at && 
    new Date(enclosure.animal2_produced_at).getTime() + (animal2.produces_interval_minutes * 60 * 1000) <= currentTime;
  
  const getProductionProgress = (producedAt: string | null, intervalMinutes: number): number => {
    if (!producedAt) return 0;
    const startTime = new Date(producedAt).getTime();
    const intervalMs = intervalMinutes * 60 * 1000;
    const elapsed = currentTime - startTime;
    const progress = Math.min(100, (elapsed / intervalMs) * 100);
    return Math.max(0, progress);
  };
  
  const getBreedingProgress = (): number => {
    if (!enclosure.breeding_started_at || !enclosure.breeding_completes_at) return 0;
    const startTime = new Date(enclosure.breeding_started_at).getTime();
    const endTime = new Date(enclosure.breeding_completes_at).getTime();
    const totalDuration = endTime - startTime;
    const elapsed = currentTime - startTime;
    const progress = Math.min(100, (elapsed / totalDuration) * 100);
    return Math.max(0, progress);
  };
  
  const productionProgress1 = animal1 && enclosure.animal1_produced_at && !canCollect1
    ? getProductionProgress(enclosure.animal1_produced_at, animal1.produces_interval_minutes)
    : 0;
  const productionProgress2 = animal2 && enclosure.animal2_produced_at && !canCollect2
    ? getProductionProgress(enclosure.animal2_produced_at, animal2.produces_interval_minutes)
    : 0;

  const isEmpty = enclosure.animal1_id === null && enclosure.animal2_id === null;

  const animalsMatch = animal1 && animal2 && animal1.id === animal2.id;
  const animal1AtMax = enclosure.animal1_level !== null && enclosure.animal1_level >= 10;
  const animal2AtMax = enclosure.animal2_level !== null && enclosure.animal2_level >= 10;
  const canBreed = animalsMatch && !animal1AtMax && !animal2AtMax && !enclosure.breeding_started_at;
  const breedingComplete = enclosure.breeding_completes_at &&
    new Date(enclosure.breeding_completes_at).getTime() <= currentTime;

  const breedingProgress = enclosure.breeding_started_at && !breedingComplete
    ? getBreedingProgress()
    : 0;
  
  const animal1Level = enclosure.animal1_level ?? 0;
  const animal2Level = enclosure.animal2_level ?? 0;

  const getAnimalTooltipContent = (animal: AnimalType, level: number, slot: 1 | 2): TooltipSection[] => {
    const sections: TooltipSection[] = [];

    sections.push({
      title: `${animal.name}${level > 0 ? ` +${level}` : ''}`,
      content: `Rarity: ${animal.rarity}`,
      color: animal.rarity === 'legendary' ? 'purple' : animal.rarity === 'rare' ? 'blue' : 'gray',
      icon: animal.icon
    });

    if (animal.produces_item_id) {
      const isProducing = slot === 1 ? !canCollect1 : !canCollect2;
      const statusText = isProducing ? 'Currently producing...' : 'Ready to collect!';
      sections.push({
        title: 'Production',
        content: `${getItemIcon(animal.produces_item_id)} ${getItemName(animal.produces_item_id)} x${animal.produces_quantity} every ${animal.produces_interval_minutes} minutes\n${statusText}`,
        color: isProducing ? 'yellow' : 'green',
        icon: '⚡'
      });
    }

    return sections;
  };

  const formatTimeLeft = (completesAt: string): string => {
    const now = Date.now();
    const completes = new Date(completesAt).getTime();
    const diff = completes - now;
    if (diff <= 0) return 'Ready!';
    const minutes = Math.floor(diff / (1000 * 60));
    return `${minutes}m`;
  };

  const handleSelectAnimal = async (animalTypeId: number) => {
    if (showAnimalModal === null) return;
    await onAddAnimal(enclosure.id, animalTypeId, showAnimalModal);
    setShowAnimalModal(null);
  };

  const handleWatchAd = async (slot: number) => {
    const productionId = enclosure.id * 10 + slot;
    await watchAdForSpeedUp('zoo', productionId);
  };

  return (
    <div className="bg-gradient-to-br from-green-900 to-emerald-900 rounded-2xl p-6 border-2 border-green-500/30 shadow-lg">
      <div className="flex justify-between items-center mb-4">
        <h3 className="text-xl font-bold text-white">{enclosure.enclosure_name}</h3>
        {isEmpty && (
          <button
            onClick={() => onDeleteEnclosure(enclosure.id)}
            className="w-6 h-6 flex items-center justify-center bg-red-600 hover:bg-red-500 text-white rounded-full text-xs font-bold transition-colors"
            title="Delete enclosure"
          >
            ×
          </button>
        )}
      </div>
      
      <div className="grid grid-cols-2 gap-4 mb-4">
        <div className="bg-white/10 rounded-lg p-4 relative">
          {animal1 ? (
            <>
              <button
                onClick={() => onRemoveAnimal(enclosure.id, 1)}
                className="absolute top-2 right-2 w-6 h-6 flex items-center justify-center bg-red-600 hover:bg-red-500 text-white rounded-full text-xs font-bold transition-colors"
                title="Remove animal"
              >
                ×
              </button>
              <Tooltip content={getAnimalTooltipContent(animal1, animal1Level, 1)} position="auto">
                <div className="text-center mb-2">
                  <span className="text-4xl">{animal1.icon}</span>
                  <div className="text-white font-semibold text-sm">{animal1.name}</div>
                  {animal1Level > 0 && (
                    <div className="text-yellow-400 text-xs font-bold">+{animal1Level}</div>
                  )}
                  <div className="text-slate-300 text-xs capitalize">{animal1.rarity}</div>
                </div>
              </Tooltip>
              {canCollect1 && (
                <button
                  onClick={() => onCollectProduction(enclosure.id, 1)}
                  className="w-full px-3 py-2 bg-green-600 hover:bg-green-500 text-white rounded-lg font-semibold text-sm transition-colors"
                >
                  Collect {getItemIcon(animal1.produces_item_id || 0)} {animal1.produces_quantity}
                </button>
              )}
              {!canCollect1 && animal1 && enclosure.animal1_produced_at && (
                <div className="space-y-2">
                  <div className="text-xs text-yellow-300 text-center font-semibold">
                    Producing...
                  </div>
                  <div className="flex items-center gap-2">
                    <div className="flex-1">
                      <ProgressBar
                        progress={productionProgress1}
                        showLabel={true}
                        label={`${Math.round(productionProgress1)}%`}
                      />
                    </div>
                    <button
                      onClick={() => onCancelProduction(enclosure.id, 1)}
                      className="w-6 h-6 flex items-center justify-center bg-red-600 hover:bg-red-500 text-white rounded-full text-xs font-bold transition-colors flex-shrink-0"
                      title="Cancel production"
                    >
                      ×
                    </button>
                  </div>
                  {canWatchAd && (
                    <button
                      onClick={() => handleWatchAd(1)}
                      disabled={adLoading}
                      className="w-full px-2 py-1 bg-green-600 hover:bg-green-500 disabled:bg-gray-600 disabled:cursor-not-allowed text-white text-xs rounded-lg font-semibold transition-colors"
                      title={`Watch Ad (${adsRemaining} remaining)`}
                    >
                      📺 Speed Up
                    </button>
                  )}
                </div>
              )}
            </>
          ) : (
            <button
              onClick={() => setShowAnimalModal(1)}
              className="w-full h-full flex items-center justify-center text-slate-400 hover:text-white border-2 border-dashed border-slate-600 rounded-lg p-4 transition-colors"
            >
              + Add Animal
            </button>
          )}
        </div>

        <div className="bg-white/10 rounded-lg p-4 relative">
          {animal2 ? (
            <>
              <button
                onClick={() => onRemoveAnimal(enclosure.id, 2)}
                className="absolute top-2 right-2 w-6 h-6 flex items-center justify-center bg-red-600 hover:bg-red-500 text-white rounded-full text-xs font-bold transition-colors"
                title="Remove animal"
              >
                ×
              </button>
              <Tooltip content={getAnimalTooltipContent(animal2, animal2Level, 2)} position="auto">
                <div className="text-center mb-2">
                  <span className="text-4xl">{animal2.icon}</span>
                  <div className="text-white font-semibold text-sm">{animal2.name}</div>
                  {animal2Level > 0 && (
                    <div className="text-yellow-400 text-xs font-bold">+{animal2Level}</div>
                  )}
                  <div className="text-slate-300 text-xs capitalize">{animal2.rarity}</div>
                </div>
              </Tooltip>
              {canCollect2 && (
                <button
                  onClick={() => onCollectProduction(enclosure.id, 2)}
                  className="w-full px-3 py-2 bg-green-600 hover:bg-green-500 text-white rounded-lg font-semibold text-sm transition-colors"
                >
                  Collect {getItemIcon(animal2.produces_item_id || 0)} {animal2.produces_quantity}
                </button>
              )}
              {!canCollect2 && animal2 && enclosure.animal2_produced_at && (
                <div className="space-y-2">
                  <div className="text-xs text-yellow-300 text-center font-semibold">
                    Producing...
                  </div>
                  <div className="flex items-center gap-2">
                    <div className="flex-1">
                      <ProgressBar
                        progress={productionProgress2}
                        showLabel={true}
                        label={`${Math.round(productionProgress2)}%`}
                      />
                    </div>
                    <button
                      onClick={() => onCancelProduction(enclosure.id, 2)}
                      className="w-6 h-6 flex items-center justify-center bg-red-600 hover:bg-red-500 text-white rounded-full text-xs font-bold transition-colors flex-shrink-0"
                      title="Cancel production"
                    >
                      ×
                    </button>
                  </div>
                  {canWatchAd && (
                    <button
                      onClick={() => handleWatchAd(2)}
                      disabled={adLoading}
                      className="w-full px-2 py-1 bg-green-600 hover:bg-green-500 disabled:bg-gray-600 disabled:cursor-not-allowed text-white text-xs rounded-lg font-semibold transition-colors"
                      title={`Watch Ad (${adsRemaining} remaining)`}
                    >
                      📺 Speed Up
                    </button>
                  )}
                </div>
              )}
            </>
          ) : (
            <button
              onClick={() => setShowAnimalModal(2)}
              className="w-full h-full flex items-center justify-center text-slate-400 hover:text-white border-2 border-dashed border-slate-600 rounded-lg p-4 transition-colors"
            >
              + Add Animal
            </button>
          )}
        </div>
      </div>

      {enclosure.breeding_started_at && (
        <div className="mb-4 bg-purple-900/50 rounded-lg p-3">
          {breedingComplete ? (
            <button
              onClick={() => onCollectBred(enclosure.id)}
              className="w-full px-4 py-2 bg-purple-600 hover:bg-purple-500 text-white rounded-lg font-semibold transition-colors"
            >
              Collect Bred Animal! 🎉
            </button>
          ) : (
            <div className="space-y-2">
              <div className="text-xs text-purple-300 text-center font-semibold">
                Breeding...
              </div>
              <div className="flex items-center gap-2">
                <div className="flex-1">
                  <ProgressBar
                    progress={breedingProgress}
                    showLabel={true}
                    label={`${Math.round(breedingProgress)}%`}
                  />
                </div>
                <button
                  onClick={() => onCancelBreeding(enclosure.id)}
                  className="w-6 h-6 flex items-center justify-center bg-red-600 hover:bg-red-500 text-white rounded-full text-xs font-bold transition-colors flex-shrink-0"
                  title="Cancel breeding"
                >
                  ×
                </button>
              </div>
              <div className="text-xs text-purple-300 text-center">{formatTimeLeft(enclosure.breeding_completes_at!)}</div>
            </div>
          )}
        </div>
      )}

      {animal1 && animal2 && !enclosure.breeding_started_at && (
        <>
          {canBreed ? (
            <button
              onClick={() => onStartBreeding(enclosure.id)}
              className="w-full px-4 py-2 bg-purple-600 hover:bg-purple-500 text-white rounded-lg font-semibold transition-colors"
            >
              Start Breeding 💕
            </button>
          ) : (
            <div className="w-full px-4 py-2 bg-slate-700 text-slate-400 rounded-lg text-center text-sm">
              {!animalsMatch ? (
                <span>Can only breed two animals of the same type</span>
              ) : animal1AtMax || animal2AtMax ? (
                <span>Cannot breed animals at maximum level (+10)</span>
              ) : (
                <span>Cannot breed</span>
              )}
            </div>
          )}
        </>
      )}

      {showAnimalModal !== null && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowAnimalModal(null)}>
          <div className="bg-gradient-to-br from-green-900 to-emerald-900 rounded-2xl p-6 max-w-2xl w-full mx-4 border-2 border-green-500/50 max-h-[80vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-2xl font-bold text-white mb-4">Select Animal for Slot {showAnimalModal}</h3>
            <div className="grid grid-cols-2 md:grid-cols-3 gap-4 mb-4">
              {animalTypes.map((animal) => (
                <button
                  key={animal.id}
                  onClick={() => handleSelectAnimal(animal.id)}
                  className={`bg-gradient-to-br ${
                    animal.rarity === 'legendary' ? 'from-purple-600 to-pink-600' :
                    animal.rarity === 'rare' ? 'from-blue-600 to-indigo-600' :
                    'from-gray-600 to-slate-600'
                  } rounded-xl p-4 border-2 border-white/20 hover:scale-105 transition-all text-left`}
                >
                  <div className="text-center">
                    <div className="text-4xl mb-2">{animal.icon}</div>
                    <div className="text-white font-semibold text-sm mb-1">{animal.name}</div>
                    <div className="text-yellow-400 text-xs mb-1">💎 {animal.base_cost_crystals}</div>
                    <div className="text-white/80 text-xs capitalize">{animal.rarity}</div>
                    {animal.produces_item_id && (
                      <div className="text-white/90 text-xs mt-1">
                        Produces: {getItemIcon(animal.produces_item_id)} every {animal.produces_interval_minutes}m
                      </div>
                    )}
                  </div>
                </button>
              ))}
            </div>
            <button
              onClick={() => setShowAnimalModal(null)}
              className="w-full px-4 py-2 bg-red-600 hover:bg-red-500 text-white rounded-lg font-semibold transition-colors"
            >
              Cancel
            </button>
          </div>
        </div>
      )}
    </div>
  );
});

EnclosureCard.displayName = 'EnclosureCard';

export default function ZooPage() {
  const {
    enclosures,
    animalTypes,
    loading,
    error,
    enclosureCostInfo,
    fetchEnclosures,
    fetchAnimalTypes,
    createEnclosure,
    addAnimalToEnclosure,
    removeAnimalFromEnclosure,
    collectProduction,
    startBreeding,
    collectBredAnimal,
    deleteEnclosure,
    cancelBreeding,
    cancelProduction,
    subscribeToZoo
  } = useZooStore();
  const { crystals } = usePlayerStore();
  const { showError } = useErrorHandler();
  const [newEnclosureName, setNewEnclosureName] = useState('');
  const [showCreateModal, setShowCreateModal] = useState(false);
  
  const handleAddAnimal = useCallback(async (enclosureId: number, animalTypeId: number, slot: number) => {
    const enclosure = enclosures.find(e => e.id === enclosureId);
    if (enclosure) {
      if (slot === 1 && enclosure.animal1_id !== null) {
        showError(
          'Enclosure Slot Occupied',
          'Slot 1 in this enclosure is already occupied by another animal.',
          { slot: 1 },
          'Select an empty slot or remove the current animal first.'
        );
        return;
      }
      if (slot === 2 && enclosure.animal2_id !== null) {
        showError(
          'Enclosure Slot Occupied',
          'Slot 2 in this enclosure is already occupied by another animal.',
          { slot: 2 },
          'Select an empty slot or remove the current animal first.'
        );
        return;
      }
    }
    
    const animalType = animalTypes.find(a => a.id === animalTypeId);
    if (animalType && crystals < animalType.base_cost_crystals) {
      const needed = animalType.base_cost_crystals - crystals;
      showError(
        'Not Enough Crystals',
        `You need ${needed.toLocaleString()} more crystals to purchase this animal.`,
        { resource: 'crystals', required: animalType.base_cost_crystals, available: crystals },
        'Earn more crystals by completing orders, harvesting crops, or selling items.'
      );
      return;
    }
    
    await addAnimalToEnclosure(enclosureId, animalTypeId, slot);
  }, [enclosures, animalTypes, crystals, showError, addAnimalToEnclosure]);

  useEffect(() => {
    fetchEnclosures();
    fetchAnimalTypes();
    const unsubscribe = subscribeToZoo();
    return unsubscribe;
  }, [fetchEnclosures, fetchAnimalTypes, subscribeToZoo]);

  const handleCreateEnclosure = useCallback(async () => {
    const trimmedName = newEnclosureName.trim();
    if (!trimmedName) {
      showError('Enclosure Name Required', 'Please enter a name for your enclosure.');
      return;
    }
    if (trimmedName.length > 30) {
      showError('Enclosure Name Too Long', 'Enclosure name cannot exceed 30 characters.');
      return;
    }
    // Allow only alphanumeric characters, spaces, hyphens, and apostrophes
    if (!/^[a-zA-Z0-9\s\-']+$/.test(trimmedName)) {
      showError('Invalid Enclosure Name', 'Enclosure name can only contain letters, numbers, spaces, hyphens, and apostrophes.');
      return;
    }
    await createEnclosure(trimmedName);
    setNewEnclosureName('');
    setShowCreateModal(false);
  }, [newEnclosureName, showError, createEnclosure]);

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-green-900 via-emerald-900 to-teal-900 p-4">
        <div className="max-w-6xl mx-auto">
          <h1 className="text-3xl font-bold text-white mb-6 text-center">Zoo</h1>
          <div className="flex justify-center">
            <Skeleton className="w-full h-64" />
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-green-900 via-emerald-900 to-teal-900 p-4">
      <div className="max-w-6xl mx-auto">
        <div className="flex justify-between items-center mb-6">
          <h1 className="text-3xl font-bold text-white">Zoo</h1>
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-2 px-4 py-2 bg-slate-800/60 rounded-lg">
              <span className="text-2xl">💎</span>
              <span className="text-white font-mono">{crystals.toLocaleString()}</span>
            </div>
            {enclosureCostInfo && (
              <div className="flex items-center gap-2 px-4 py-2 bg-slate-800/60 rounded-lg">
                <span className="text-white text-sm">
                  Enclosures: {enclosureCostInfo.current_count}/{enclosureCostInfo.max_enclosures}
                </span>
              </div>
            )}
            <button
              onClick={() => setShowCreateModal(true)}
              disabled={enclosureCostInfo?.at_limit && crystals < (enclosureCostInfo?.next_cost || 0)}
              className="px-4 py-2 bg-green-600 hover:bg-green-500 disabled:bg-gray-600 disabled:cursor-not-allowed text-white rounded-lg font-semibold transition-colors"
            >
              + New Enclosure
              {enclosureCostInfo && enclosureCostInfo.next_cost > 0 && (
                <span className="ml-2 text-xs">({enclosureCostInfo.next_cost} 💎)</span>
              )}
            </button>
          </div>
        </div>

        {error && (
          <div className="mb-6 p-4 bg-red-500/20 border border-red-500/50 rounded-xl text-red-200 text-center">
            {error}
          </div>
        )}

        {enclosures.length === 0 ? (
          <div className="bg-white/10 backdrop-blur-md rounded-2xl p-8 text-center">
            <p className="text-slate-300 text-lg mb-4">No enclosures yet</p>
            <p className="text-slate-400 mb-4">Create your first enclosure to start collecting animals!</p>
            {enclosureCostInfo && enclosureCostInfo.next_cost > 0 && (
              <p className="text-yellow-400 text-sm mb-4">
                Next enclosure costs {enclosureCostInfo.next_cost} crystals
              </p>
            )}
            <button
              onClick={() => setShowCreateModal(true)}
              disabled={enclosureCostInfo?.at_limit && crystals < (enclosureCostInfo?.next_cost || 0)}
              className="px-6 py-3 bg-green-600 hover:bg-green-500 disabled:bg-gray-600 disabled:cursor-not-allowed text-white rounded-lg font-semibold transition-colors"
            >
              Create Enclosure
            </button>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {enclosures.map((enclosure) => (
              <EnclosureCard
                key={enclosure.id}
                enclosure={enclosure}
                animalTypes={animalTypes}
                onAddAnimal={handleAddAnimal}
                onRemoveAnimal={removeAnimalFromEnclosure}
                onCollectProduction={collectProduction}
                onStartBreeding={startBreeding}
                onCollectBred={collectBredAnimal}
                onDeleteEnclosure={deleteEnclosure}
                onCancelBreeding={cancelBreeding}
                onCancelProduction={cancelProduction}
              />
            ))}
          </div>
        )}

        <div className="mt-8">
          <h2 className="text-2xl font-bold text-white mb-4">Available Animals</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {animalTypes.map((animal) => (
              <div
                key={animal.id}
                className={`bg-gradient-to-br ${
                  animal.rarity === 'legendary' ? 'from-purple-600 to-pink-600' :
                  animal.rarity === 'rare' ? 'from-blue-600 to-indigo-600' :
                  'from-gray-600 to-slate-600'
                } rounded-xl p-4 border border-white/20`}
              >
                <div className="text-center">
                  <div className="text-4xl mb-2">{animal.icon}</div>
                  <div className="text-white font-semibold mb-1">{animal.name}</div>
                  <div className="text-yellow-400 text-sm mb-2">💎 {animal.base_cost_crystals}</div>
                  <div className="text-white/80 text-xs capitalize mb-2">{animal.rarity}</div>
                  {animal.produces_item_id && (
                    <div className="text-white/90 text-xs">
                      Produces: {getItemIcon(animal.produces_item_id)} {getItemName(animal.produces_item_id)} every {animal.produces_interval_minutes}m
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>

        {showCreateModal && (
          <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowCreateModal(false)}>
            <div className="bg-gradient-to-br from-slate-800 to-slate-900 rounded-2xl p-6 max-w-md w-full mx-4 border-2 border-slate-700" onClick={(e) => e.stopPropagation()}>
              <h3 className="text-2xl font-bold text-white mb-4">Create Enclosure</h3>
              {enclosureCostInfo && (
                <div className="mb-4 p-3 bg-slate-700/50 rounded-lg">
                  <div className="text-slate-300 text-sm mb-1">
                    Current: {enclosureCostInfo.current_count}/{enclosureCostInfo.max_enclosures} enclosures
                  </div>
                  {enclosureCostInfo.next_cost > 0 && (
                    <div className="text-yellow-400 text-sm">
                      Cost: {enclosureCostInfo.next_cost} crystals
                    </div>
                  )}
                  {enclosureCostInfo.can_create_free && (
                    <div className="text-green-400 text-sm">Free!</div>
                  )}
                </div>
              )}
              <input
                type="text"
                value={newEnclosureName}
                onChange={(e) => setNewEnclosureName(e.target.value)}
                placeholder="Enclosure name..."
                className="w-full px-4 py-2 bg-slate-700 text-white rounded-lg mb-4"
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    handleCreateEnclosure();
                  }
                }}
              />
              <div className="flex gap-2">
                <button
                  onClick={() => setShowCreateModal(false)}
                  className="flex-1 px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg font-semibold transition-colors"
                >
                  Cancel
                </button>
                <button
                  onClick={handleCreateEnclosure}
                  disabled={enclosureCostInfo?.at_limit && crystals < (enclosureCostInfo?.next_cost || 0)}
                  className="flex-1 px-4 py-2 bg-green-600 hover:bg-green-500 disabled:bg-gray-600 disabled:cursor-not-allowed text-white rounded-lg font-semibold transition-colors"
                >
                  Create
                  {enclosureCostInfo && enclosureCostInfo.next_cost > 0 && (
                    <span className="ml-2">({enclosureCostInfo.next_cost} 💎)</span>
                  )}
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}


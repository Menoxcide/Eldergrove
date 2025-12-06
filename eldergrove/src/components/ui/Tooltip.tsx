'use client';

import React, { useState, useRef, useEffect, useCallback, ReactNode } from 'react';
import { createPortal } from 'react-dom';

export type TooltipPosition = 'top' | 'bottom' | 'left' | 'right' | 'auto';

export interface TooltipSection {
  title?: string;
  content: ReactNode;
  color?: 'blue' | 'green' | 'red' | 'purple' | 'yellow' | 'gray';
  icon?: string;
}

export interface TooltipProps {
  content: ReactNode | TooltipSection[];
  position?: TooltipPosition;
  delay?: number;
  children: React.ReactElement;
  className?: string;
  maxWidth?: string;
}

const Tooltip: React.FC<TooltipProps> = ({
  content,
  position = 'auto',
  delay = 300,
  children,
  className = '',
  maxWidth = '320px',
}) => {
  const [isVisible, setIsVisible] = useState(false);
  const [calculatedPosition, setCalculatedPosition] = useState<TooltipPosition>('top');
  const [tooltipStyle, setTooltipStyle] = useState<React.CSSProperties>({});
  const [mousePosition, setMousePosition] = useState({ x: 0, y: 0 });
  const timeoutRef = useRef<NodeJS.Timeout | null>(null);
  const tooltipRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLElement>(null);
  const positionUpdateRef = useRef<number | null>(null);
  const tooltipId = useRef(`tooltip-${Math.random().toString(36).substr(2, 9)}`);

  const isMobile = typeof window !== 'undefined' && ('ontouchstart' in window || navigator.maxTouchPoints > 0);

  const showTooltip = (x?: number, y?: number) => {
    if (timeoutRef.current) {
      clearTimeout(timeoutRef.current);
    }
    timeoutRef.current = setTimeout(() => {
      if (x !== undefined && y !== undefined) {
        setMousePosition({ x, y });
      }
      setIsVisible(true);
    }, delay);
  };

  const hideTooltip = () => {
    if (timeoutRef.current) {
      clearTimeout(timeoutRef.current);
      timeoutRef.current = null;
    }
    if (positionUpdateRef.current) {
      cancelAnimationFrame(positionUpdateRef.current);
      positionUpdateRef.current = null;
    }
    setIsVisible(false);
  };

  const calculatePosition = useCallback(() => {
    if (!isVisible || !tooltipRef.current) {
      return;
    }

    const tooltip = tooltipRef.current;
    const tooltipRect = tooltip.getBoundingClientRect();

    if (tooltipRect.width === 0 || tooltipRect.height === 0) {
      positionUpdateRef.current = requestAnimationFrame(calculatePosition);
      return;
    }

    const viewportWidth = window.innerWidth;
    const viewportHeight = window.innerHeight;
    const spacing = 8;

    let top = mousePosition.y;
    let left = mousePosition.x;

    // Adjust position based on preferred position or auto
    if (position !== 'auto') {
      switch (position) {
        case 'top':
          top = mousePosition.y - tooltipRect.height - spacing;
          left = mousePosition.x - tooltipRect.width / 2;
          break;
        case 'bottom':
          top = mousePosition.y + spacing;
          left = mousePosition.x - tooltipRect.width / 2;
          break;
        case 'left':
          top = mousePosition.y - tooltipRect.height / 2;
          left = mousePosition.x - tooltipRect.width - spacing;
          break;
        case 'right':
          top = mousePosition.y - tooltipRect.height / 2;
          left = mousePosition.x + spacing;
          break;
      }
    } else {
      // Auto positioning: prefer bottom, then top, right, left
      const spaceBottom = viewportHeight - mousePosition.y;
      const spaceTop = mousePosition.y;
      const spaceRight = viewportWidth - mousePosition.x;
      const spaceLeft = mousePosition.x;

      if (spaceBottom >= tooltipRect.height + spacing) {
        top = mousePosition.y + spacing;
        left = mousePosition.x - tooltipRect.width / 2;
        setCalculatedPosition('bottom');
      } else if (spaceTop >= tooltipRect.height + spacing) {
        top = mousePosition.y - tooltipRect.height - spacing;
        left = mousePosition.x - tooltipRect.width / 2;
        setCalculatedPosition('top');
      } else if (spaceRight >= tooltipRect.width + spacing) {
        top = mousePosition.y - tooltipRect.height / 2;
        left = mousePosition.x + spacing;
        setCalculatedPosition('right');
      } else if (spaceLeft >= tooltipRect.width + spacing) {
        top = mousePosition.y - tooltipRect.height / 2;
        left = mousePosition.x - tooltipRect.width - spacing;
        setCalculatedPosition('left');
      } else {
        // Fallback to bottom
        top = mousePosition.y + spacing;
        left = mousePosition.x - tooltipRect.width / 2;
        setCalculatedPosition('bottom');
      }
    }

    // Ensure tooltip stays within viewport
    left = Math.max(8, Math.min(left, viewportWidth - tooltipRect.width - 8));
    top = Math.max(8, Math.min(top, viewportHeight - tooltipRect.height - 8));

    setTooltipStyle({
      position: 'fixed',
      top: `${top}px`,
      left: `${left}px`,
      zIndex: 9999,
    });
  }, [isVisible, position, mousePosition]);

  useEffect(() => {
    if (isVisible) {
      positionUpdateRef.current = requestAnimationFrame(calculatePosition);
    }

    return () => {
      if (positionUpdateRef.current) {
        cancelAnimationFrame(positionUpdateRef.current);
        positionUpdateRef.current = null;
      }
    };
  }, [isVisible, calculatePosition]);

  useEffect(() => {
    if (!isVisible) return;

    const updatePosition = () => {
      if (positionUpdateRef.current) {
        cancelAnimationFrame(positionUpdateRef.current);
      }
      positionUpdateRef.current = requestAnimationFrame(calculatePosition);
    };

    window.addEventListener('scroll', updatePosition, true);
    window.addEventListener('resize', updatePosition);

    return () => {
      window.removeEventListener('scroll', updatePosition, true);
      window.removeEventListener('resize', updatePosition);
      if (positionUpdateRef.current) {
        cancelAnimationFrame(positionUpdateRef.current);
        positionUpdateRef.current = null;
      }
    };
  }, [isVisible, calculatePosition]);

  const renderContent = () => {
    if (Array.isArray(content)) {
      return (
        <div className="space-y-3">
          {content.map((section, index) => {
            const colorClasses = {
              blue: 'border-cyan-500/50 bg-cyan-950/40',
              green: 'border-emerald-500/50 bg-emerald-950/40',
              red: 'border-red-500/50 bg-red-950/40',
              purple: 'border-purple-500/50 bg-purple-950/40',
              yellow: 'border-yellow-500/50 bg-yellow-950/40',
              gray: 'border-slate-500/50 bg-slate-950/40',
            };

            const color = section.color || 'gray';
            return (
              <div
                key={index}
                className={`p-3 rounded-lg border ${colorClasses[color]} backdrop-blur-sm`}
              >
                {section.title && (
                  <div className="flex items-center gap-2 mb-2">
                    {section.icon && <span className="text-lg">{section.icon}</span>}
                    <h4 className="font-bold text-white text-sm">{section.title}</h4>
                  </div>
                )}
                <div className="text-slate-200 text-xs leading-relaxed">
                  {section.content}
                </div>
              </div>
            );
          })}
        </div>
      );
    }
    return <div className="text-slate-200 text-sm leading-relaxed">{content}</div>;
  };

  const childProps = children.props as Record<string, any>;
  const originalRef = (children as React.ReactElement & { ref?: React.Ref<HTMLElement> }).ref;

  const handleMouseMove = (e: React.MouseEvent) => {
    setMousePosition({ x: e.clientX, y: e.clientY });
  };

  const handleTouchStart = (e: React.TouchEvent) => {
    const touch = e.touches[0];
    setMousePosition({ x: touch.clientX, y: touch.clientY });
    showTooltip(touch.clientX, touch.clientY);
    e.preventDefault(); // Prevent mouse events
  };

  const handleTouchEnd = () => {
    hideTooltip();
  };

  const childWithRef = React.cloneElement<any>(children, {
    ref: (node: HTMLElement | null) => {
      triggerRef.current = node;
      if (typeof originalRef === 'function') {
        originalRef(node);
      } else if (originalRef && 'current' in originalRef) {
        (originalRef as React.MutableRefObject<HTMLElement | null>).current = node;
      }
    },
    'aria-describedby': isVisible ? tooltipId.current : undefined,
    ...(isMobile ? {
      onTouchStart: (e: React.TouchEvent) => {
        handleTouchStart(e);
        childProps.onTouchStart?.(e);
      },
      onTouchEnd: (e: React.TouchEvent) => {
        handleTouchEnd();
        childProps.onTouchEnd?.(e);
      },
    } : {
      onMouseEnter: (e: React.MouseEvent) => {
        showTooltip(e.clientX, e.clientY);
        childProps.onMouseEnter?.(e);
      },
      onMouseLeave: (e: React.MouseEvent) => {
        hideTooltip();
        childProps.onMouseLeave?.(e);
      },
      onMouseMove: (e: React.MouseEvent) => {
        handleMouseMove(e);
        childProps.onMouseMove?.(e);
      },
      onFocus: (e: React.FocusEvent) => {
        showTooltip();
        childProps.onFocus?.(e);
      },
      onBlur: (e: React.FocusEvent) => {
        hideTooltip();
        childProps.onBlur?.(e);
      },
    }),
  });

  return (
    <>
      {childWithRef}
      {isVisible &&
        createPortal(
          <div
            id={tooltipId.current}
            ref={tooltipRef}
            style={tooltipStyle}
            className={`pointer-events-none transition-opacity duration-200 ${
              isVisible ? 'opacity-100' : 'opacity-0'
            } ${className}`}
            role="tooltip"
          >
            <div
              className="bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 rounded-xl p-4 shadow-2xl border-2 border-slate-700/50 backdrop-blur-md"
              style={{ maxWidth }}
            >
              {renderContent()}
            </div>
            <div
              className={`absolute w-0 h-0 ${
                calculatedPosition === 'top'
                  ? 'top-full left-1/2 -translate-x-1/2 border-t-slate-800 border-l-transparent border-r-transparent border-t-[8px] border-l-[8px] border-r-[8px]'
                  : calculatedPosition === 'bottom'
                  ? 'bottom-full left-1/2 -translate-x-1/2 border-b-slate-800 border-l-transparent border-r-transparent border-b-[8px] border-l-[8px] border-r-[8px]'
                  : calculatedPosition === 'left'
                  ? 'left-full top-1/2 -translate-y-1/2 border-l-slate-800 border-t-transparent border-b-transparent border-l-[8px] border-t-[8px] border-b-[8px]'
                  : 'right-full top-1/2 -translate-y-1/2 border-r-slate-800 border-t-transparent border-b-transparent border-r-[8px] border-t-[8px] border-b-[8px]'
              }`}
            />
          </div>,
          document.body
        )}
    </>
  );
};

export default Tooltip;
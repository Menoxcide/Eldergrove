import ProtectedLayout from '@/components/layout/ProtectedLayout';
import ResourceBar from '@/components/game/ResourceBar';
import BottomNav from '@/components/layout/BottomNav';

export default function GameLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <ProtectedLayout>
      <ResourceBar />
      <div className="flex-1 pb-20">
        {children}
      </div>
      <BottomNav />
    </ProtectedLayout>
  );
}

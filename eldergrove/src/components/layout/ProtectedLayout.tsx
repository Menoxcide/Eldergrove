'use client';

import React from 'react';

interface ProtectedLayoutProps {
  children: React.ReactNode;
}

const ProtectedLayout: React.FC<ProtectedLayoutProps> = ({ children }) => {
  // Trust the middleware completely - if we reach this component,
  // the middleware has already validated the session
  return <>{children}</>;
};

export default ProtectedLayout;
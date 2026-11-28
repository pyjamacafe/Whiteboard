import React from 'react';

export type IconName =
  | 'pen'
  | 'sharpie'
  | 'fill'
  | 'eraser'
  | 'select'
  | 'scenes'
  | 'home'
  | 'undo'
  | 'redo'
  | 'trash'
  | 'copy'
  | 'paste'
  | 'duplicate'
  | 'image'
  | 'center'
  | 'fit'
  | 'moon'
  | 'sun'
  | 'warmPaper'
  | 'rename'
  | 'handTap'
  | 'pencilOnly'
  | 'saveWB'
  | 'exportPNG'
  | 'exportPDF'
  | 'openFile'
  | 'help'
  | 'about'
  | 'more'
  | 'chevronLeft'
  | 'chevronRight'
  | 'plus'
  | 'minus'
  | 'grid'
  | 'dots'
  | 'ruled'
  | 'plain'
  | 'clock'
  | 'folder'
  | 'pin'
  | 'pinSlash'
  | 'search'
  | 'list'
  | 'thumbnails'
  | 'sort'
  | 'lock'
  | 'wand'
  | 'arrowsH'
  | 'replace'
  | 'blend'
  | 'circleFull'
  | 'circleDotted'
  | 'layers'
  | 'sliders'
  | 'dock'
  | 'rotateReset'
  | 'zoomIn'
  | 'zoomOut'
  | 'restore'
  | 'close'
  | 'check'
  | 'arrowUp'
  | 'arrowDown'
  | 'externalLink';

interface IconProps {
  name: IconName;
  size?: number;
  className?: string;
}

export const Icon: React.FC<IconProps> = ({ name, size = 18, className }) => {
  const common: React.SVGProps<SVGSVGElement> = {
    width: size,
    height: size,
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: 1.85,
    strokeLinecap: 'round',
    strokeLinejoin: 'round',
    className,
    'aria-hidden': true,
  };

  switch (name) {
    case 'pen':
      // pencil.tip silhouette
      return (
        <svg {...common}>
          <path d="M12 3L7.5 13.5V20.5H16.5V13.5L12 3Z" />
          <path d="M7.5 13.5H16.5" />
          <path d="M10.2 7.2H13.8" />
        </svg>
      );
    case 'sharpie':
      // highlighter chisel-tip silhouette
      return (
        <svg {...common}>
          <path d="M9.5 4L14.5 6.5V11H9.5V4Z" />
          <path d="M7.5 11H16.5L17.5 20.5H6.5L7.5 11Z" />
          <path d="M7.2 15.5H16.8" />
        </svg>
      );
    case 'fill':
      // paint.bucket.classic silhouette
      return (
        <svg {...common}>
          <path d="M5.5 11.5L11.5 5.5L18.5 12.5L13 18C12 19 10.4 19 9.4 18L5.5 14.1C4.5 13.1 4.5 12.5 5.5 11.5Z" />
          <path d="M9.5 3.5L13.5 7.5" />
          <path d="M19 15.2C19 15.2 21 17.4 21 18.8C21 19.9 20.1 20.8 19 20.8C17.9 20.8 17 19.9 17 18.8C17 17.4 19 15.2 19 15.2Z" fill="currentColor" stroke="none" />
        </svg>
      );
    case 'eraser':
      return (
        <svg {...common}>
          <path d="M4.5 16.5L13.2 7.8C14.1 6.9 15.5 6.9 16.4 7.8L19.7 11.1C20.6 12 20.6 13.4 19.7 14.3L14.5 19.5H7.5L4.5 16.5Z" />
          <path d="M9.5 11.5L15.5 17.5" />
          <path d="M14.5 19.5H20.5" />
        </svg>
      );
    case 'select':
      // lasso silhouette
      return (
        <svg {...common}>
          <ellipse cx="12" cy="10.5" rx="7.5" ry="5.5" />
          <circle cx="9" cy="16" r="1.6" />
          <path d="M9 17.6C9 19.5 10.6 21 13 21C14.8 21 16 20.1 16.5 19.2" />
        </svg>
      );
    case 'scenes':
      return (
        <svg {...common}>
          <rect x="4" y="8" width="16" height="11" rx="2.2" />
          <path d="M7 5H17" />
          <path d="M9.5 2.5H14.5" />
        </svg>
      );
    case 'home':
      return (
        <svg {...common}>
          <path d="M3.5 10.8L12 4L20.5 10.8" />
          <path d="M5.5 9.5V19.5H18.5V9.5" />
          <path d="M10 19.5V14H14V19.5" />
        </svg>
      );
    case 'undo':
      return (
        <svg {...common}>
          <path d="M9 14L4 9L9 4" />
          <path d="M4 9H14.5C17.8 9 20 11.2 20 14.5C20 17.8 17.8 20 14.5 20H11" />
        </svg>
      );
    case 'redo':
      return (
        <svg {...common}>
          <path d="M15 14L20 9L15 4" />
          <path d="M20 9H9.5C6.2 9 4 11.2 4 14.5C4 17.8 6.2 20 9.5 20H13" />
        </svg>
      );
    case 'trash':
      return (
        <svg {...common}>
          <path d="M4.5 7H19.5" />
          <path d="M9.5 4H14.5" />
          <path d="M6.5 7L7.5 19.5H16.5L17.5 7" />
          <path d="M10 11V16" />
          <path d="M14 11V16" />
        </svg>
      );
    case 'copy':
      return (
        <svg {...common}>
          <rect x="9" y="9" width="11" height="11" rx="2" />
          <path d="M5 15H4.5C3.7 15 3 14.3 3 13.5V4.5C3 3.7 3.7 3 4.5 3H13.5C14.3 3 15 3.7 15 4.5V5" />
        </svg>
      );
    case 'paste':
      return (
        <svg {...common}>
          <rect x="5" y="5" width="14" height="16" rx="2" />
          <path d="M9 3.5H15V6.5H9V3.5Z" />
        </svg>
      );
    case 'duplicate':
      return (
        <svg {...common}>
          <rect x="8.5" y="8.5" width="11.5" height="11.5" rx="2" />
          <path d="M14.2 11.5V17" />
          <path d="M11.5 14.2H17" />
          <path d="M5.5 15H5C4.2 15 3.5 14.3 3.5 13.5V5C3.5 4.2 4.2 3.5 5 3.5H13.5C14.3 3.5 15 4.2 15 5V5.5" />
        </svg>
      );
    case 'image':
      return (
        <svg {...common}>
          <rect x="3.5" y="5" width="17" height="14" rx="2.2" />
          <circle cx="9" cy="10" r="1.5" />
          <path d="M20.5 15.5L15.5 11L9 17.5" />
          <path d="M12 14.5L9.5 12.5L4.5 17.5" />
        </svg>
      );
    case 'center':
      return (
        <svg {...common}>
          <path d="M4 8V5.5C4 4.7 4.7 4 5.5 4H8" />
          <path d="M16 4H18.5C19.3 4 20 4.7 20 5.5V8" />
          <path d="M20 16V18.5C20 19.3 19.3 20 18.5 20H16" />
          <path d="M8 20H5.5C4.7 20 4 19.3 4 18.5V16" />
          <circle cx="12" cy="12" r="2.5" />
        </svg>
      );
    case 'fit':
      return (
        <svg {...common}>
          <path d="M4 9V4H9" />
          <path d="M4 4L10 10" />
          <path d="M20 15V20H15" />
          <path d="M20 20L14 14" />
        </svg>
      );
    case 'moon':
      return (
        <svg {...common}>
          <path d="M19.5 14.5A7.5 7.5 0 0 1 9.5 4.5A7.5 7.5 0 1 0 19.5 14.5Z" fill="currentColor" stroke="none" />
        </svg>
      );
    case 'sun':
      return (
        <svg {...common}>
          <circle cx="12" cy="12" r="4" fill="currentColor" />
          <path d="M12 2.5V5M12 19V21.5M4.9 4.9L6.7 6.7M17.3 17.3L19.1 19.1M2.5 12H5M19 12H21.5M4.9 19.1L6.7 17.3M17.3 6.7L19.1 4.9" />
        </svg>
      );
    case 'warmPaper':
      return (
        <svg {...common}>
          <path d="M4.5 9.5H16.5V14.5C16.5 17 14.5 18.5 12 18.5H9C6.5 18.5 4.5 17 4.5 14.5V9.5Z" />
          <path d="M16.5 11H18.5C19.6 11 20.5 11.9 20.5 13C20.5 14.1 19.6 15 18.5 15H16.5" />
          <path d="M4 21H17" />
          <path d="M8.5 6.5C8.5 5.2 9.5 5.2 9.5 4" />
          <path d="M12.5 6.5C12.5 5.2 13.5 5.2 13.5 4" />
        </svg>
      );
    case 'rename':
      return (
        <svg {...common}>
          <path d="M12 4V20" />
          <path d="M9 4H15" />
          <path d="M9 20H15" />
          <path d="M5 9H9" />
          <path d="M15 9H19" />
        </svg>
      );
    case 'handTap':
      return (
        <svg {...common}>
          <path d="M11 11V5.5C11 4.7 11.7 4 12.5 4C13.3 4 14 4.7 14 5.5V11" />
          <path d="M14 10.5C14 9.7 14.7 9 15.5 9C16.3 9 17 9.7 17 10.5V12" />
          <path d="M17 11.5C17 10.7 17.7 10 18.5 10C19.3 10 20 10.7 20 11.5V15.5C20 18.5 17.5 21 14.5 21H12C9.5 21 7.8 19.6 6.5 17.5L4.8 14.6C4.4 13.9 4.6 13 5.3 12.6C6 12.2 6.9 12.4 7.3 13.1L9 15.5V11" />
        </svg>
      );
    case 'pencilOnly':
      return (
        <svg {...common}>
          <path d="M4 20L8.2 18.8L19.5 7.5C20.2 6.8 20.2 5.7 19.5 5L19 4.5C18.3 3.8 17.2 3.8 16.5 4.5L5.2 15.8L4 20Z" />
          <path d="M14.5 6.5L17.5 9.5" />
        </svg>
      );
    case 'saveWB':
      return (
        <svg {...common}>
          <path d="M12 4V15" />
          <path d="M8 11L12 15L16 11" />
          <path d="M4.5 15.5V18.5C4.5 19.3 5.2 20 6 20H18C18.8 20 19.5 19.3 19.5 18.5V15.5" />
        </svg>
      );
    case 'exportPNG':
      return (
        <svg {...common}>
          <rect x="3.5" y="4.5" width="14" height="12" rx="2" />
          <path d="M18 12V19.5" />
          <path d="M15.2 16.8L18 19.5L20.8 16.8" />
          <circle cx="8" cy="8.5" r="1.2" />
          <path d="M4.5 14.5L9 10.5L13 14.5" />
        </svg>
      );
    case 'exportPDF':
      return (
        <svg {...common}>
          <path d="M6 3.5H14.5L18.5 7.5V20.5H6V3.5Z" />
          <path d="M14.5 3.5V7.5H18.5" />
          <path d="M9 12H15.5" />
          <path d="M9 15.5H13.5" />
        </svg>
      );
    case 'openFile':
    case 'folder':
      return (
        <svg {...common}>
          <path d="M3.5 7.5C3.5 6.4 4.4 5.5 5.5 5.5H9.5L11.5 7.5H18.5C19.6 7.5 20.5 8.4 20.5 9.5V17.5C20.5 18.6 19.6 19.5 18.5 19.5H5.5C4.4 19.5 3.5 18.6 3.5 17.5V7.5Z" />
        </svg>
      );
    case 'help':
      return (
        <svg {...common}>
          <circle cx="12" cy="12" r="9" />
          <path d="M9.5 9.5C9.5 8.1 10.6 7 12 7C13.4 7 14.5 8.1 14.5 9.5C14.5 10.6 13.7 11.4 12.6 11.8C12.2 12 12 12.3 12 12.8V13.5" />
          <circle cx="12" cy="16.5" r="0.8" fill="currentColor" stroke="none" />
        </svg>
      );
    case 'about':
      return (
        <svg {...common}>
          <circle cx="12" cy="12" r="9" />
          <path d="M12 11V16.5" />
          <circle cx="12" cy="7.8" r="0.9" fill="currentColor" stroke="none" />
        </svg>
      );
    case 'more':
      return (
        <svg {...common}>
          <circle cx="5.5" cy="12" r="1.6" fill="currentColor" stroke="none" />
          <circle cx="12" cy="12" r="1.6" fill="currentColor" stroke="none" />
          <circle cx="18.5" cy="12" r="1.6" fill="currentColor" stroke="none" />
        </svg>
      );
    case 'chevronLeft':
      return (
        <svg {...common}>
          <path d="M15 6L9 12L15 18" />
        </svg>
      );
    case 'chevronRight':
      return (
        <svg {...common}>
          <path d="M9 6L15 12L9 18" />
        </svg>
      );
    case 'plus':
      return (
        <svg {...common}>
          <path d="M12 5V19M5 12H19" />
        </svg>
      );
    case 'minus':
      return (
        <svg {...common}>
          <path d="M5 12H19" />
        </svg>
      );
    case 'grid':
      return (
        <svg {...common}>
          <rect x="4" y="4" width="16" height="16" rx="2" />
          <path d="M9.3 4V20M14.7 4V20M4 9.3H20M4 14.7H20" />
        </svg>
      );
    case 'dots':
      return (
        <svg {...common}>
          {[6, 12, 18].map((x) =>
            [6, 12, 18].map((y) => (
              <circle key={`${x}-${y}`} cx={x} cy={y} r="1.3" fill="currentColor" stroke="none" />
            ))
          )}
        </svg>
      );
    case 'ruled':
      return (
        <svg {...common}>
          <path d="M4 6H20M4 10H20M4 14H20M4 18H20" />
        </svg>
      );
    case 'plain':
      return (
        <svg {...common}>
          <rect x="4" y="5" width="16" height="14" rx="2" />
        </svg>
      );
    case 'clock':
      return (
        <svg {...common}>
          <circle cx="12" cy="12" r="9" />
          <path d="M12 7.5V12L15 14" />
        </svg>
      );
    case 'pin':
      return (
        <svg {...common}>
          <path d="M15 4.5L19.5 9L17 11.5L15.5 10L12.5 13L13.5 16L11.5 18L7.5 14L4 17.5" />
          <path d="M10.5 11L6 6.5L8 4.5L11 5.5L14 2.5" />
        </svg>
      );
    case 'pinSlash':
      return (
        <svg {...common}>
          <path d="M4 4L20 20" />
          <path d="M15 4.5L19.5 9L17 11.5" />
          <path d="M9.5 15.5L4 20" />
        </svg>
      );
    case 'search':
      return (
        <svg {...common}>
          <circle cx="11" cy="11" r="6.5" />
          <path d="M16 16L20.5 20.5" />
        </svg>
      );
    case 'list':
      return (
        <svg {...common}>
          <path d="M8 6H20M8 12H20M8 18H20" />
          <circle cx="4.5" cy="6" r="1" fill="currentColor" stroke="none" />
          <circle cx="4.5" cy="12" r="1" fill="currentColor" stroke="none" />
          <circle cx="4.5" cy="18" r="1" fill="currentColor" stroke="none" />
        </svg>
      );
    case 'thumbnails':
      return (
        <svg {...common}>
          <rect x="4" y="4" width="6.5" height="6.5" rx="1.4" />
          <rect x="13.5" y="4" width="6.5" height="6.5" rx="1.4" />
          <rect x="4" y="13.5" width="6.5" height="6.5" rx="1.4" />
          <rect x="13.5" y="13.5" width="6.5" height="6.5" rx="1.4" />
        </svg>
      );
    case 'sort':
      return (
        <svg {...common}>
          <path d="M8 5V19M8 5L4.5 8.5M8 5L11.5 8.5" />
          <path d="M16 19V5M16 19L12.5 15.5M16 19L19.5 15.5" />
        </svg>
      );
    case 'lock':
      return (
        <svg {...common}>
          <rect x="5.5" y="10.5" width="13" height="9.5" rx="2" />
          <path d="M8.5 10.5V7.5C8.5 5.6 10.1 4 12 4C13.9 4 15.5 5.6 15.5 7.5V10.5" />
        </svg>
      );
    case 'wand':
      return (
        <svg {...common}>
          <path d="M4.5 19.5L15 9" />
          <path d="M15 4V6.5M15 11.5V14M10 9H12.5M17.5 9H20" />
          <path d="M12 6L13.2 7.2M16.8 10.8L18 12" />
        </svg>
      );
    case 'arrowsH':
      return (
        <svg {...common}>
          <path d="M4 12H20" />
          <path d="M8 8L4 12L8 16" />
          <path d="M16 8L20 12L16 16" />
        </svg>
      );
    case 'replace':
      return (
        <svg {...common}>
          <rect x="4" y="4" width="10.5" height="10.5" rx="2" fill="currentColor" />
          <rect x="9.5" y="9.5" width="10.5" height="10.5" rx="2" />
        </svg>
      );
    case 'blend':
      return (
        <svg {...common}>
          <rect x="4" y="4" width="10.5" height="10.5" rx="2" />
          <rect x="9.5" y="9.5" width="10.5" height="10.5" rx="2" />
        </svg>
      );
    case 'circleFull':
      return (
        <svg {...common}>
          <circle cx="12" cy="12" r="7.5" fill="currentColor" stroke="none" />
        </svg>
      );
    case 'circleDotted':
      return (
        <svg {...common}>
          <circle cx="12" cy="12" r="7.5" strokeDasharray="3 3" />
        </svg>
      );
    case 'layers':
      return (
        <svg {...common}>
          <path d="M12 4L3.5 8.5L12 13L20.5 8.5L12 4Z" />
          <path d="M3.5 12.5L12 17L20.5 12.5" />
          <path d="M3.5 16.5L12 21L20.5 16.5" />
        </svg>
      );
    case 'sliders':
      return (
        <svg {...common}>
          <path d="M4 7H20M4 12H20M4 17H20" />
          <circle cx="9" cy="7" r="2" fill="currentColor" />
          <circle cx="15" cy="12" r="2" fill="currentColor" />
          <circle cx="10" cy="17" r="2" fill="currentColor" />
        </svg>
      );
    case 'dock':
      return (
        <svg {...common}>
          <rect x="3.5" y="4.5" width="17" height="15" rx="2.2" />
          <path d="M7.5 16H16.5" strokeWidth="2.4" />
        </svg>
      );
    case 'rotateReset':
      return (
        <svg {...common}>
          <path d="M4.5 11A7.5 7.5 0 1 1 6.7 17.3" />
          <path d="M4.5 6.5V11H9" />
        </svg>
      );
    case 'zoomIn':
      return (
        <svg {...common}>
          <circle cx="10.5" cy="10.5" r="6.5" />
          <path d="M15.5 15.5L20 20" />
          <path d="M10.5 8V13M8 10.5H13" />
        </svg>
      );
    case 'zoomOut':
      return (
        <svg {...common}>
          <circle cx="10.5" cy="10.5" r="6.5" />
          <path d="M15.5 15.5L20 20" />
          <path d="M8 10.5H13" />
        </svg>
      );
    case 'restore':
      return (
        <svg {...common}>
          <path d="M3.5 12A8.5 8.5 0 1 0 6 6" />
          <path d="M3.5 4V8.5H8" />
        </svg>
      );
    case 'close':
      return (
        <svg {...common}>
          <path d="M6 6L18 18M18 6L6 18" />
        </svg>
      );
    case 'check':
      return (
        <svg {...common}>
          <path d="M5 12.5L10 17.5L19 7" />
        </svg>
      );
    case 'arrowUp':
      return (
        <svg {...common}>
          <path d="M12 19V5M6.5 10.5L12 5L17.5 10.5" />
        </svg>
      );
    case 'arrowDown':
      return (
        <svg {...common}>
          <path d="M12 5V19M6.5 13.5L12 19L17.5 13.5" />
        </svg>
      );
    case 'externalLink':
      return (
        <svg {...common}>
          <path d="M14 4H20V10" />
          <path d="M10 14L20 4" />
          <path d="M18 14V18.5C18 19.3 17.3 20 16.5 20H5.5C4.7 20 4 19.3 4 18.5V7.5C4 6.7 4.7 6 5.5 6H10" />
        </svg>
      );
  }
};

# FlightTool - Personal Flight Tracking Application

## Overview

FlightTool is a full-stack web application for personal flight tracking and management. It allows users to log their flights, visualize flight routes, analyze travel statistics, and import flight data from CSV files. The application features a modern, aviation-themed interface built with React and shadcn/ui components.

## User Preferences

Preferred communication style: Simple, everyday language.

## System Architecture

### Frontend Architecture
- **Framework**: React 18 with TypeScript
- **Build Tool**: Vite for fast development and optimized production builds
- **Routing**: Wouter for lightweight client-side routing
- **UI Components**: shadcn/ui component library with Radix UI primitives
- **Styling**: Tailwind CSS with custom aviation-themed color palette
- **State Management**: TanStack Query (React Query) for server state management
- **Form Handling**: React Hook Form with Zod validation

### Backend Architecture
- **Runtime**: Node.js with Express.js framework
- **Language**: TypeScript with ES modules
- **Database**: PostgreSQL with Drizzle ORM
- **Authentication**: Replit Auth with OpenID Connect
- **Session Management**: Express sessions with PostgreSQL storage
- **File Uploads**: Multer for CSV import functionality

### Key Design Decisions

**Monorepo Structure**: The application uses a monorepo structure with separate `client`, `server`, and `shared` directories. This allows for code sharing between frontend and backend while maintaining clear separation of concerns.

**Type Safety**: Full TypeScript implementation across the stack with shared schemas using Drizzle Zod for consistent validation between client and server.

**Authentication Strategy**: Replit Auth integration provides seamless authentication within the Replit environment, handling user sessions and profile management automatically.

## Key Components

### Database Schema
- **Users Table**: Stores user profiles from Replit Auth (ID, email, name, profile image)
- **Flights Table**: Core flight data including dates, airports, airlines, aircraft details, and personal notes
- **Airports Table**: Reference data for airport information and codes
- **Airlines Table**: Reference data for airline information and codes
- **Sessions Table**: Session storage for user authentication

### API Routes
- **Authentication**: `/api/auth/user` - User profile management
- **Flights**: CRUD operations for flight management, CSV import functionality
- **Airports/Airlines**: Reference data endpoints
- **Statistics**: Aggregated flight statistics and analytics

### Frontend Pages
- **Landing**: Unauthenticated home page with feature overview
- **Dashboard**: Overview with statistics and recent flights
- **Flights**: Flight list with search functionality
- **Add Flight**: Form for manual flight entry
- **Import CSV**: File upload interface for bulk flight import
- **Flight Map**: Visualization interface (placeholder for future map integration)

## Data Flow

1. **Authentication**: Users authenticate through Replit Auth, creating/updating user records
2. **Flight Management**: Users can manually add flights or import from CSV files
3. **Data Validation**: All flight data is validated using shared Zod schemas
4. **Statistics Generation**: Backend aggregates flight data for dashboard analytics
5. **Real-time Updates**: TanStack Query manages cache invalidation for immediate UI updates

## External Dependencies

### Core Framework Dependencies
- **@neondatabase/serverless**: PostgreSQL database driver optimized for serverless environments
- **drizzle-orm**: Type-safe SQL query builder and ORM
- **@tanstack/react-query**: Server state management for React
- **wouter**: Lightweight routing library for React

### UI and Styling
- **@radix-ui/***: Unstyled, accessible UI primitives
- **tailwindcss**: Utility-first CSS framework
- **class-variance-authority**: Utility for creating variant-based component APIs
- **lucide-react**: Icon library

### Authentication and Session Management
- **openid-client**: OpenID Connect client for Replit Auth
- **passport**: Authentication middleware
- **express-session**: Session management
- **connect-pg-simple**: PostgreSQL session store

### Development Tools
- **vite**: Build tool and development server
- **typescript**: Type checking and compilation
- **eslint**: Code linting
- **prettier**: Code formatting

## Deployment Strategy

### Development Environment
- **Hot Reload**: Vite development server with HMR
- **Database**: PostgreSQL instance with automatic migrations
- **Environment Variables**: Database URL, session secrets, and Replit Auth configuration

### Production Build
- **Frontend**: Vite builds optimized static assets
- **Backend**: esbuild compiles TypeScript server code to ESM format
- **Static Serving**: Express serves built frontend assets in production
- **Database Migrations**: Drizzle Kit handles schema migrations

### Replit Integration
- **Authentication**: Native Replit Auth integration
- **Database**: Configured for Replit's PostgreSQL service
- **Development Banner**: Automatic dev environment detection
- **Hot Reloading**: Replit-specific development tools integration

The application is designed to run seamlessly on Replit with minimal configuration, leveraging Replit's built-in services for authentication and database management while maintaining the ability to be deployed on other platforms with environment variable adjustments.
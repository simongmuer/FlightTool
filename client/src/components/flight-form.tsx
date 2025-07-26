import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useToast } from "@/hooks/use-toast";
import { useLocation } from "wouter";
import { apiRequest } from "@/lib/queryClient";
import { isUnauthorizedError } from "@/lib/authUtils";
import { insertFlightSchema, type InsertFlightData } from "@shared/schema";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from "@/components/ui/form";

export default function FlightForm() {
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [, setLocation] = useLocation();

  const form = useForm<InsertFlightData>({
    resolver: zodResolver(insertFlightSchema),
    defaultValues: {
      date: new Date(),
      flightNumber: "",
      fromAirport: "",
      toAirport: "",
      fromAirportCode: "",
      toAirportCode: "",
      departureTime: "",
      arrivalTime: "",
      duration: "",
      airline: "",
      aircraftType: "",
      registration: "",
      seatNumber: "",
      seatType: "",
      flightClass: "",
      flightReason: "",
      notes: "",
    },
  });

  const createFlightMutation = useMutation({
    mutationFn: async (data: InsertFlightData) => {
      const response = await apiRequest("POST", "/api/flights", data);
      return response.json();
    },
    onSuccess: () => {
      toast({
        title: "Success",
        description: "Flight added successfully!",
      });
      queryClient.invalidateQueries({ queryKey: ["/api/flights"] });
      queryClient.invalidateQueries({ queryKey: ["/api/stats"] });
      setLocation("/flights");
    },
    onError: (error) => {
      if (isUnauthorizedError(error)) {
        toast({
          title: "Unauthorized",
          description: "You are logged out. Logging in again...",
          variant: "destructive",
        });
        setTimeout(() => {
          window.location.href = "/api/login";
        }, 500);
        return;
      }
      toast({
        title: "Error",
        description: "Failed to add flight. Please try again.",
        variant: "destructive",
      });
    },
  });

  const onSubmit = (data: InsertFlightData) => {
    createFlightMutation.mutate(data);
  };

  return (
    <Form {...form}>
      <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-6">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <FormField
            control={form.control}
            name="flightNumber"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Flight Number</FormLabel>
                <FormControl>
                  <Input placeholder="e.g. LH452" {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="airline"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Airline</FormLabel>
                <FormControl>
                  <Input placeholder="e.g. Lufthansa (LH/DLH)" {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <FormField
            control={form.control}
            name="fromAirport"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Departure Airport</FormLabel>
                <FormControl>
                  <Input placeholder="e.g. Frankfurt am Main / Frankfurt (FRA/EDDF)" {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="toAirport"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Arrival Airport</FormLabel>
                <FormControl>
                  <Input placeholder="e.g. Los Angeles / Los Angeles International (LAX/KLAX)" {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <FormField
            control={form.control}
            name="fromAirportCode"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Departure Code</FormLabel>
                <FormControl>
                  <Input placeholder="e.g. FRA" {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="toAirportCode"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Arrival Code</FormLabel>
                <FormControl>
                  <Input placeholder="e.g. LAX" {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <FormField
            control={form.control}
            name="date"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Flight Date</FormLabel>
                <FormControl>
                  <Input
                    type="date"
                    {...field}
                    value={field.value instanceof Date ? field.value.toISOString().split('T')[0] : field.value}
                    onChange={(e) => field.onChange(new Date(e.target.value))}
                  />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="departureTime"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Departure Time</FormLabel>
                <FormControl>
                  <Input type="time" {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="arrivalTime"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Arrival Time</FormLabel>
                <FormControl>
                  <Input type="time" {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <FormField
            control={form.control}
            name="aircraftType"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Aircraft Type</FormLabel>
                <FormControl>
                  <Input placeholder="e.g. A380-800" {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="seatNumber"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Seat Number</FormLabel>
                <FormControl>
                  <Input placeholder="e.g. 2K" {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="flightClass"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Flight Class</FormLabel>
                <Select onValueChange={field.onChange} defaultValue={field.value}>
                  <FormControl>
                    <SelectTrigger>
                      <SelectValue placeholder="Select class" />
                    </SelectTrigger>
                  </FormControl>
                  <SelectContent>
                    <SelectItem value="1">Economy</SelectItem>
                    <SelectItem value="2">Premium Economy</SelectItem>
                    <SelectItem value="3">Business</SelectItem>
                    <SelectItem value="4">First Class</SelectItem>
                  </SelectContent>
                </Select>
                <FormMessage />
              </FormItem>
            )}
          />
        </div>

        <FormField
          control={form.control}
          name="notes"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Notes (Optional)</FormLabel>
              <FormControl>
                <Textarea
                  placeholder="Flight experience, delays, etc."
                  rows={3}
                  {...field}
                />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        <div className="flex justify-end space-x-3 pt-6 border-t border-slate-200">
          <Button 
            type="button" 
            variant="outline" 
            onClick={() => setLocation("/flights")}
            disabled={createFlightMutation.isPending}
          >
            Cancel
          </Button>
          <Button 
            type="submit" 
            className="bg-aviation-blue hover:bg-blue-700"
            disabled={createFlightMutation.isPending}
          >
            {createFlightMutation.isPending ? "Adding..." : "Add Flight"}
          </Button>
        </div>
      </form>
    </Form>
  );
}
